import 'dart:convert';
import 'dart:io';

import '../health/scoring/baseline_service.dart';
import '../health/scoring/recovery_scoring_service.dart';
import '../health/scoring/scoring_types.dart';
import '../models/fitness_summary.dart';
import '../models/personal_profile.dart';
import '../models/sleep_summary.dart';
import 'account_service.dart';
import 'observability_service.dart';

class HomeserverSyncResult {
  const HomeserverSyncResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class HomeserverSyncService {
  HomeserverSyncService({AccountService? accountService})
    : _accountService = accountService ?? AccountService();

  static const _requestTimeout = Duration(seconds: 12);
  static const _baseUrl = String.fromEnvironment(
    'QUANTIVITA_API_BASE_URL',
    defaultValue: 'https://api.quantivita.bryandijkh.com',
  );

  final AccountService _accountService;

  Future<HomeserverSyncResult> sync({
    required PersonalProfile profile,
    required Map<String, double> healthSummary,
    required FitnessSummary fitnessSummary,
  }) async {
    final correlationId = ObservabilityService.instance.newCorrelationId();
    final stopwatch = Stopwatch()..start();
    final configError = _apiConfigError;
    if (configError != null) {
      return HomeserverSyncResult(success: false, message: configError);
    }

    try {
      final account = await _accountService.ensureLocalAccount();
      await _registerAccount(account);

      final client = HttpClient();
      try {
        client.connectionTimeout = _requestTimeout;
        final request = await client
            .postUrl(
              Uri.parse('$_baseUrl/api/users/${account.accountId}/ingest'),
            )
            .timeout(_requestTimeout);
        request.headers.contentType = ContentType.json;
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${account.syncToken}',
        );
        request.write(
          jsonEncode({
            'profile': {
              'age': profile.age,
              'birthDate': profile.birthDate,
              'biologicalSex': profile.biologicalSex,
              'weightKg': profile.weightKg,
              'heightCm': profile.heightCm,
              'bodyFatPercent': profile.bodyFatPercent,
            },
            'daily': [_dailyPayload(healthSummary, fitnessSummary)],
            'workouts': [
              for (final event in fitnessSummary.events) _workoutPayload(event),
            ],
          }),
        );

        final response = await request.close().timeout(_requestTimeout);
        await response.drain<void>().timeout(_requestTimeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await ObservabilityService.instance.info(
            'sync_job_completed',
            'Quantivita API sync completed',
            correlationId: correlationId,
            durationMs: stopwatch.elapsedMilliseconds,
            metadata: {
              'event_count': fitnessSummary.events.length,
              'progressa_event_count': fitnessSummary.events
                  .where((event) => event.isProgressa)
                  .length,
            },
          );
          return HomeserverSyncResult(
            success: true,
            message: 'Quantivita API synced as ${account.accountId}.',
          );
        }

        await ObservabilityService.instance.error(
          'sync_job_failed',
          'Homeserver sync failed',
          correlationId: correlationId,
          errorCode: 'QV-SYNC-001',
          durationMs: stopwatch.elapsedMilliseconds,
          metadata: {'status_code': response.statusCode},
        );
        return HomeserverSyncResult(
          success: false,
          message: 'Homeserver sync failed (${response.statusCode}).',
        );
      } finally {
        client.close(force: true);
      }
    } catch (error) {
      await ObservabilityService.instance.error(
        'sync_job_failed',
        'Homeserver sync unavailable',
        correlationId: correlationId,
        errorCode: 'QV-SYNC-001',
        durationMs: stopwatch.elapsedMilliseconds,
        metadata: {'error_type': error.runtimeType.toString()},
      );
      return HomeserverSyncResult(
        success: false,
        message: 'Homeserver sync is tijdelijk niet beschikbaar.',
      );
    }
  }

  Future<void> _registerAccount(QuantivitaAccount account) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = _requestTimeout;
      final request = await client
          .postUrl(Uri.parse('$_baseUrl/api/accounts/register'))
          .timeout(_requestTimeout);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'accountId': account.accountId,
          'syncToken': account.syncToken,
          'appleLinked': account.isAppleLinked,
        }),
      );
      final response = await request.close().timeout(_requestTimeout);
      await response.drain<void>().timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Account registration failed (${response.statusCode}).',
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  String? get _apiConfigError {
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null || uri.host.isEmpty) {
      return 'Quantivita API is niet goed geconfigureerd.';
    }
    if (uri.scheme != 'https' && uri.host != 'localhost') {
      return 'Quantivita API vereist een veilige HTTPS endpoint.';
    }
    return null;
  }

  Map<String, Object?> _dailyPayload(
    Map<String, double> summary,
    FitnessSummary fitnessSummary,
  ) {
    final sleep = SleepSummary.fromSummary(summary);
    final sleepScore = sleep.qualityScore;
    final hrv = summary['hrvMs'] ?? 0;
    final restingHeartRate = summary['restingHeartBpm'] ?? 0;
    final respiratoryRate = summary['respiratoryRate'] ?? 0;
    final bodyTemperature = summary['bodyTemperatureC'] ?? 0;
    final wristTemperature = summary['wristTemperatureC'] ?? 0;
    final temperatureDeviation = wristTemperature > 0 && bodyTemperature > 0
        ? wristTemperature - bodyTemperature
        : null;
    final baselines = BaselineService.fromToday(
      hrvMs: hrv,
      restingHeartRate: restingHeartRate,
      sleepMinutes: sleep.totalMinutes,
      sleepEfficiency: sleep.efficiency,
      strainLoad: fitnessSummary.cardioLoad.toDouble(),
      stressScore: 0,
      respiratoryRate: respiratoryRate,
      temperatureDeviation: temperatureDeviation ?? 0,
    );
    final recovery = RecoveryScoringService.calculate(
      input: RecoveryScoreInput(
        sleepDurationMinutes: sleep.totalMinutes,
        sleepScore: sleepScore,
        sleepAvailable: sleep.totalMinutes > 0,
        hrvRmssd: hrv,
        restingHeartRate: restingHeartRate,
        strainLoadToday: fitnessSummary.cardioLoad.toDouble(),
        stressScore: 0,
        respiratoryRate: respiratoryRate > 0 ? respiratoryRate : null,
        temperatureDeviation: temperatureDeviation,
      ),
      baselines: baselines,
    );
    return {
      'date': DateTime.now().toIso8601String().split('T').first,
      'recoveryScore': recovery.score,
      'sleepScore': sleepScore,
      'strainScore': fitnessSummary.strain,
      'calibrationStatus': recovery.calibrationStatus.wireName,
      'sleepMinutes': summary['sleepMinutes'],
      'hrvMs': summary['hrvMs'],
      'restingHeartBpm': summary['restingHeartBpm'],
      'respiratoryRate': summary['respiratoryRate'],
      'oxygenSaturation': summary['oxygenSaturation'],
      'activeEnergyKcal': summary['activeEnergyKcal'],
      'steps': summary['steps'],
      'bodyTemperatureC': summary['bodyTemperatureC'],
      'wristTemperatureC': summary['wristTemperatureC'],
    };
  }

  Map<String, Object?> _workoutPayload(FitnessEventSummary event) {
    return {
      'id': event.sourceUuid.isNotEmpty ? event.sourceUuid : event.id,
      'source': event.source,
      'externalWorkoutId': event.externalWorkoutId,
      'title': event.displayTitle,
      'startTime': event.startTime,
      'durationMinutes': event.effectiveDurationMinutes,
      'energyKcal': event.effectiveEnergyKcal,
      'totalEnergyKcal': event.totalEnergyKcal > 0
          ? event.totalEnergyKcal
          : event.effectiveEnergyKcal,
      'distanceMeters': event.distanceMeters,
      'elevationGainMeters': event.elevationGainMeters,
      'averageHeartRate': event.averageHeartRate,
      'maxHeartRate': event.maxHeartRate,
      'temperatureC': event.temperatureC,
      'humidityPercent': event.humidityPercent,
      'weatherCondition': event.weatherCondition,
      'airQualityIndex': event.airQualityIndex,
      'hasRoute': event.hasRoute,
      if (event.progressaDetails.isNotEmpty)
        'progressaDetails': event.progressaDetails,
    };
  }
}
