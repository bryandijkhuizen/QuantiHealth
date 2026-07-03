import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fitness_summary.dart';
import 'account_service.dart';
import 'observability_service.dart';

class ProgressaIntegrationResult {
  const ProgressaIntegrationResult({
    required this.success,
    required this.message,
    this.workouts = const [],
    this.connected,
  });

  final bool success;
  final String message;
  final List<FitnessEventSummary> workouts;
  final bool? connected;
}

class ProgressaIntegrationService {
  ProgressaIntegrationService({AccountService? accountService})
    : _accountService = accountService ?? AccountService();

  static const _baseUrl = String.fromEnvironment(
    'QUANTIVITA_API_BASE_URL',
    defaultValue: 'https://api.quantivita.bryandijkh.com',
  );
  static const _progressaAuthBaseUrl = String.fromEnvironment(
    'PROGRESSA_AUTH_BASE_URL',
    defaultValue: 'https://api.progressa.bryandijkh.com',
  );
  static const _progressaRedirectUri = String.fromEnvironment(
    'PROGRESSA_REDIRECT_URI',
    defaultValue: 'quantivita://quantivita.app/progressa-auth',
  );
  static const _channel = MethodChannel('quantivita/progressa');

  final AccountService _accountService;

  Future<ProgressaIntegrationResult> connect() async {
    try {
      final account = await _accountService.ensureLocalAccount();
      await _registerAccount(account);
      final state = _newState();
      final query = {
        'redirect_uri': _progressaRedirectUri,
        'state': state,
        'scope': 'workouts:read',
      };
      final appAuthUrl = Uri(
        scheme: 'progressa',
        host: 'quantivita-connect',
        queryParameters: query,
      ).toString();
      final webAuthUrl = Uri.parse(
        '$_progressaAuthBaseUrl/quantivita/connect',
      ).replace(queryParameters: query).toString();
      final authResponse = await _channel
          .invokeMapMethod<String, Object?>('authorizeProgressa', {
            'authUrl': appAuthUrl,
            'fallbackAuthUrl': webAuthUrl,
            'redirectUri': _progressaRedirectUri,
            'state': state,
          });
      final code = authResponse?['code']?.toString();
      if (code == null || code.isEmpty) {
        return const ProgressaIntegrationResult(
          success: false,
          message: 'Progressa did not return an authorization code.',
        );
      }

      final response = await _jsonRequest(
        method: 'POST',
        path: '/api/users/${account.accountId}/integrations/progressa/exchange',
        token: account.syncToken,
        body: {'code': code},
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const ProgressaIntegrationResult(
          success: true,
          message: 'Progressa connected to Quantivita.',
        );
      }
      return ProgressaIntegrationResult(
        success: false,
        message: 'Progressa connect failed (${response.statusCode}).',
      );
    } on PlatformException catch (error) {
      return ProgressaIntegrationResult(
        success: false,
        message: error.message ?? 'Progressa authorization was cancelled.',
      );
    } catch (error) {
      return ProgressaIntegrationResult(
        success: false,
        message: 'Progressa connect failed: $error',
      );
    }
  }

  Future<ProgressaIntegrationResult> disconnect() async {
    try {
      final account = await _accountService.ensureLocalAccount();
      await _registerAccount(account);
      final response = await _jsonRequest(
        method: 'DELETE',
        path: '/api/users/${account.accountId}/integrations/progressa',
        token: account.syncToken,
      );
      return ProgressaIntegrationResult(
        success: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode >= 200 && response.statusCode < 300
            ? 'Progressa disconnected.'
            : 'Progressa disconnect failed (${response.statusCode}).',
      );
    } catch (error) {
      return ProgressaIntegrationResult(
        success: false,
        message: 'Progressa disconnect failed: $error',
      );
    }
  }

  Future<ProgressaIntegrationResult> isConnected() async {
    try {
      final account = await _accountService.ensureLocalAccount();
      await _registerAccount(account);
      final response = await _jsonRequest(
        method: 'GET',
        path: '/api/users/${account.accountId}/integrations/progressa',
        token: account.syncToken,
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final connected = decoded['connected'] == true;
        return ProgressaIntegrationResult(
          success: true,
          connected: connected,
          message: connected
              ? 'Progressa connected.'
              : 'Progressa not connected.',
        );
      }
      return ProgressaIntegrationResult(
        success: false,
        connected: false,
        message: 'Progressa status check failed (${response.statusCode}).',
      );
    } catch (error) {
      return ProgressaIntegrationResult(
        success: false,
        connected: false,
        message: 'Progressa status check failed: $error',
      );
    }
  }

  Future<ProgressaIntegrationResult> fetchWorkouts({
    DateTime? from,
    DateTime? to,
    int limit = 50,
  }) async {
    final correlationId = ObservabilityService.instance.newCorrelationId();
    final stopwatch = Stopwatch()..start();
    try {
      final account = await _accountService.ensureLocalAccount();
      await _registerAccount(account);
      final query = <String, String>{
        'limit': '$limit',
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
      };
      final uri = Uri.parse(
        '$_baseUrl/api/users/${account.accountId}/integrations/progressa/workouts',
      ).replace(queryParameters: query);
      final client = HttpClient();
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${account.syncToken}',
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final rawWorkouts = (decoded['workouts'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
        await _saveCachedWorkouts(account.accountId, rawWorkouts);
        final workouts = rawWorkouts.map(_eventFromJson).toList();
        final totalSets = workouts.fold<int>(
          0,
          (sum, workout) => sum + workout.progressaSetCount,
        );
        final totalExercises = workouts.fold<int>(
          0,
          (sum, workout) => sum + workout.progressaExerciseCount,
        );
        await ObservabilityService.instance.info(
          'workout_sync_completed',
          'Progressa workouts synced into Quantivita',
          correlationId: correlationId,
          durationMs: stopwatch.elapsedMilliseconds,
          metadata: {
            'workout_count': workouts.length,
            'set_count': totalSets,
            'exercise_count': totalExercises,
          },
        );
        return ProgressaIntegrationResult(
          success: true,
          message:
              'Progressa synced ${workouts.length} workouts, $totalSets sets, $totalExercises exercises.',
          workouts: workouts,
        );
      }

      final cached = await loadCachedWorkouts();
      if (cached.isNotEmpty) {
        return ProgressaIntegrationResult(
          success: true,
          message:
              'Progressa sync failed (${response.statusCode}); showing cached workouts.',
          workouts: cached,
        );
      }

      final message = _serverErrorMessage(
        body,
        fallback: 'Progressa workout fetch failed (${response.statusCode}).',
      );
      await ObservabilityService.instance.error(
        'workout_sync_failed',
        message,
        correlationId: correlationId,
        errorCode: 'QV-SYNC-001',
        durationMs: stopwatch.elapsedMilliseconds,
        metadata: {'status_code': response.statusCode},
      );
      return ProgressaIntegrationResult(success: false, message: message);
    } catch (error) {
      final cached = await loadCachedWorkouts();
      if (cached.isNotEmpty) {
        return ProgressaIntegrationResult(
          success: true,
          message: 'Progressa sync failed; showing cached workouts.',
          workouts: cached,
        );
      }
      await ObservabilityService.instance.error(
        'workout_sync_failed',
        'Progressa workout fetch failed',
        correlationId: correlationId,
        errorCode: 'QV-SYNC-001',
        durationMs: stopwatch.elapsedMilliseconds,
        metadata: {'error_type': error.runtimeType.toString()},
      );
      return ProgressaIntegrationResult(
        success: false,
        message: 'Progressa workout fetch failed: $error',
      );
    } finally {
      if (stopwatch.elapsedMilliseconds > 10000) {
        unawaited(
          ObservabilityService.instance.warn(
            'workout_sync_slow',
            'Progressa workout sync was slow',
            correlationId: correlationId,
            errorCode: 'QV-PERF-001',
            durationMs: stopwatch.elapsedMilliseconds,
          ),
        );
      }
    }
  }

  Future<List<FitnessEventSummary>> loadCachedWorkouts() async {
    final account = await _accountService.loadAccount();
    if (account == null) return const [];

    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_cachedWorkoutsKey(account.accountId));
    if (encoded == null || encoded.isEmpty) return const [];

    try {
      final decoded = jsonDecode(encoded) as List;
      return decoded
          .whereType<Map>()
          .map((item) => _eventFromJson(item.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _serverErrorMessage(String body, {required String fallback}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return fallback;
      final error = decoded['error']?.toString().trim() ?? '';
      final details = decoded['details']?.toString().trim() ?? '';
      if (error.isEmpty) return fallback;
      return details.isEmpty ? error : '$error: $details';
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _saveCachedWorkouts(
    String accountId,
    List<Map<String, dynamic>> workouts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedWorkoutsKey(accountId), jsonEncode(workouts));
  }

  String _cachedWorkoutsKey(String accountId) {
    return 'progressa.workouts.cache.$accountId';
  }

  Future<HttpClientResponse> _jsonRequest({
    required String method,
    required String path,
    required String token,
    Map<String, Object?>? body,
  }) async {
    final client = HttpClient();
    final request = await client.openUrl(method, Uri.parse('$_baseUrl$path'));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    client.close();
    return response;
  }

  Future<void> _registerAccount(QuantivitaAccount account) async {
    final client = HttpClient();
    final request = await client.postUrl(
      Uri.parse('$_baseUrl/api/accounts/register'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'accountId': account.accountId,
        'syncToken': account.syncToken,
        'appleLinked': account.isAppleLinked,
      }),
    );
    final response = await request.close();
    await response.drain<void>();
    client.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Quantivita account registration failed (${response.statusCode}).',
      );
    }
  }

  FitnessEventSummary _eventFromJson(Map<String, dynamic> json) {
    return FitnessEventSummary(
      id: json['id']?.toString() ?? '',
      sourceUuid: json['externalWorkoutId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Progressa workout',
      subtitle: 'Progressa • ${_setsLabel(json['progressaDetails'])}',
      value: _setsLabel(json['progressaDetails']),
      startTime: _epochSeconds(json['startTime']),
      durationMinutes: _double(json['durationMinutes']),
      energyKcal: _double(json['energyKcal']),
      totalEnergyKcal: _double(json['totalEnergyKcal'] ?? json['energyKcal']),
      distanceMeters: _double(json['distanceMeters']),
      elevationGainMeters: _double(json['elevationGainMeters']),
      averageHeartRate: _double(json['averageHeartRate']),
      maxHeartRate: _double(json['maxHeartRate']),
      temperatureC: _double(json['temperatureC']),
      humidityPercent: _double(json['humidityPercent']),
      weatherCondition: json['weatherCondition']?.toString() ?? '',
      airQualityIndex: _double(json['airQualityIndex']),
      typeCode: (_double(json['typeCode']) <= 0 ? 5 : _double(json['typeCode']))
          .round(),
      hasRoute: json['hasRoute'] == true,
      source: json['source']?.toString() ?? 'progressa',
      externalWorkoutId: json['externalWorkoutId']?.toString() ?? '',
      progressaDetails:
          (json['progressaDetails'] as Map?)?.cast<String, Object?>() ??
          const {},
    );
  }

  String _setsLabel(Object? details) {
    final map = details is Map ? details : const {};
    final sets = (map['totalSets'] as num?)?.round() ?? 0;
    final exercises = (map['exerciseCount'] as num?)?.round() ?? 0;
    if (sets <= 0 && exercises <= 0) return 'No set details';
    return '$sets sets • $exercises exercises';
  }

  double _double(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  double _epochSeconds(Object? value) {
    if (value is num) return value.toDouble();
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return 0;
    return parsed.millisecondsSinceEpoch / 1000;
  }

  String _newState() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
