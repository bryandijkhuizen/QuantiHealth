import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/fitness_summary.dart';
import 'workout_export_service.dart';

class StravaUploadResult {
  const StravaUploadResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class StravaService {
  StravaService({WorkoutExportService? exportService})
    : _exportService = exportService ?? WorkoutExportService();

  static const _requestTimeout = Duration(seconds: 15);
  static const _channel = MethodChannel('quantivita/strava');
  static const _clientId = String.fromEnvironment('STRAVA_CLIENT_ID');
  static const _clientSecret = String.fromEnvironment('STRAVA_CLIENT_SECRET');
  static const _redirectUri = String.fromEnvironment(
    'STRAVA_REDIRECT_URI',
    defaultValue: 'quantivita://quantivita.app/strava-auth',
  );
  static const _accessTokenKey = 'strava_access_token';
  static const _refreshTokenKey = 'strava_refresh_token';
  static const _expiresAtKey = 'strava_expires_at';

  final WorkoutExportService _exportService;

  Future<bool> isConnected() async {
    final tokens = await _loadTokens();
    final refreshToken = tokens[_refreshTokenKey] as String?;
    final accessToken = tokens[_accessTokenKey] as String?;
    return (refreshToken != null && refreshToken.isNotEmpty) ||
        (accessToken != null && accessToken.isNotEmpty);
  }

  Future<StravaUploadResult> disconnect() async {
    try {
      await _channel.invokeMethod<void>('clearStravaTokens');
      return const StravaUploadResult(
        success: true,
        message: 'Strava disconnected.',
      );
    } on MissingPluginException {
      return const StravaUploadResult(
        success: false,
        message: 'Strava disconnect is only available on iPhone.',
      );
    } catch (error) {
      return StravaUploadResult(
        success: false,
        message: 'Strava disconnect failed: $error',
      );
    }
  }

  Future<StravaUploadResult> connect() async {
    final configError = _configurationError;
    if (configError != null) {
      return StravaUploadResult(success: false, message: configError);
    }

    try {
      final response = await _channel
          .invokeMapMethod<String, Object?>('authorizeStrava', {
            'clientId': _clientId,
            'clientSecret': _clientSecret,
            'redirectUri': _redirectUri,
          });

      if (response == null || response['access_token'] == null) {
        return const StravaUploadResult(
          success: false,
          message: 'Strava authorization did not return an access token.',
        );
      }

      await _saveTokens(response);
      return const StravaUploadResult(
        success: true,
        message: 'Strava connected. You can upload merged workouts now.',
      );
    } on PlatformException catch (error) {
      return StravaUploadResult(
        success: false,
        message: error.message ?? 'Strava connection failed.',
      );
    } on MissingPluginException {
      return const StravaUploadResult(
        success: false,
        message: 'Strava connect is only available on iPhone.',
      );
    }
  }

  Future<StravaUploadResult> uploadMergedWorkout(
    MergedWorkoutPreview preview,
  ) async {
    if (!preview.canMerge) {
      return const StravaUploadResult(
        success: false,
        message: 'Select two or more workouts before uploading.',
      );
    }

    final tokenResult = await _validAccessToken();
    if (!tokenResult.success || tokenResult.token == null) {
      return StravaUploadResult(
        success: false,
        message: tokenResult.message ?? 'Connect Strava before uploading.',
      );
    }

    final tcxResult = await _exportService.createStravaTcx(preview);
    if (!tcxResult.success || tcxResult.filePath == null) {
      return StravaUploadResult(success: false, message: tcxResult.message);
    }

    try {
      final response = await _multipartUpload(
        accessToken: tokenResult.token!,
        filePath: tcxResult.filePath!,
        preview: preview,
      );
      final status = response.statusCode;
      final body = await response.transform(utf8.decoder).join();
      final json = body.isNotEmpty
          ? jsonDecode(body) as Map<String, dynamic>
          : {};

      if (status >= 200 && status < 300) {
        final uploadId = json['id']?.toString();
        return StravaUploadResult(
          success: true,
          message: uploadId == null
              ? 'Strava upload queued. Processing may take a moment.'
              : 'Strava upload queued as upload $uploadId. Processing may take a moment.',
        );
      }

      return StravaUploadResult(
        success: false,
        message: 'Strava upload failed ($status): ${json['message'] ?? body}',
      );
    } catch (error) {
      return StravaUploadResult(
        success: false,
        message: 'Strava upload failed: $error',
      );
    }
  }

  Future<StravaUploadResult> shareCsv(MergedWorkoutPreview preview) async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/${_safeFileName(preview.title)}-quantivita-export.csv',
      );
      await file.writeAsString(_csv(preview), flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: '${preview.title} CSV export',
          text: 'Quantivita merged workout CSV export.',
        ),
      );

      return const StravaUploadResult(
        success: true,
        message: 'CSV export is ready to share.',
      );
    } catch (error) {
      return StravaUploadResult(
        success: false,
        message: 'CSV export failed: $error',
      );
    }
  }

  Future<_TokenResult> _validAccessToken() async {
    final configError = _configurationError;
    if (configError != null) {
      return _TokenResult(success: false, message: configError);
    }

    final tokens = await _loadTokens();
    final accessToken = tokens[_accessTokenKey] as String?;
    final refreshToken = tokens[_refreshTokenKey] as String?;
    final expiresAt = tokens[_expiresAtKey] as int? ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (accessToken != null && accessToken.isNotEmpty && expiresAt > now + 60) {
      return _TokenResult(success: true, token: accessToken);
    }

    if (refreshToken == null || refreshToken.isEmpty) {
      return const _TokenResult(
        success: false,
        message: 'Connect Strava before uploading.',
      );
    }

    try {
      final client = HttpClient();
      try {
        client.connectionTimeout = _requestTimeout;
        final request = await client
            .postUrl(Uri.parse('https://www.strava.com/oauth/token'))
            .timeout(_requestTimeout);
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode({
            'client_id': _clientId,
            'client_secret': _clientSecret,
            'refresh_token': refreshToken,
            'grant_type': 'refresh_token',
          }),
        );

        final response = await request.close().timeout(_requestTimeout);
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(_requestTimeout);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          return _TokenResult(
            success: false,
            message: 'Strava token refresh failed (${response.statusCode}).',
          );
        }

        final json = jsonDecode(body) as Map<String, dynamic>;
        await _saveTokens(json);
        return _TokenResult(
          success: true,
          token: json['access_token'] as String?,
        );
      } finally {
        client.close(force: true);
      }
    } catch (error) {
      return const _TokenResult(
        success: false,
        message: 'Strava token refresh failed.',
      );
    }
  }

  Future<HttpClientResponse> _multipartUpload({
    required String accessToken,
    required String filePath,
    required MergedWorkoutPreview preview,
  }) async {
    final file = File(filePath);
    final boundary = 'quantivita-${DateTime.now().microsecondsSinceEpoch}';
    final client = HttpClient();
    client.connectionTimeout = _requestTimeout;
    final request = await client
        .postUrl(Uri.parse('https://www.strava.com/api/v3/uploads'))
        .timeout(_requestTimeout);
    try {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      void addField(String name, String value) {
        request.write('--$boundary\r\n');
        request.write('Content-Disposition: form-data; name="$name"\r\n\r\n');
        request.write('$value\r\n');
      }

      addField('name', preview.title);
      addField('description', 'Merged workout uploaded by Quantivita.');
      addField('data_type', 'tcx');
      addField(
        'external_id',
        'quantivita-${preview.startTime.round()}-${preview.endTime.round()}.tcx',
      );
      addField('trainer', '0');
      addField('commute', '0');

      request.write('--$boundary\r\n');
      request.write(
        'Content-Disposition: form-data; name="file"; filename="${file.uri.pathSegments.last}"\r\n',
      );
      request.write('Content-Type: application/vnd.garmin.tcx+xml\r\n\r\n');
      await request.addStream(file.openRead()).timeout(_requestTimeout);
      request.write('\r\n--$boundary--\r\n');

      final response = await request.close().timeout(_requestTimeout);
      client.close(force: false);
      return response;
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  Future<void> _saveTokens(Map<String, Object?> response) async {
    final accessToken = response['access_token'] as String?;
    final refreshToken = response['refresh_token'] as String?;
    final expiresAt = response['expires_at'];
    final payload = <String, Object?>{};

    if (accessToken != null) {
      payload[_accessTokenKey] = accessToken;
    }
    if (refreshToken != null) {
      payload[_refreshTokenKey] = refreshToken;
    }
    if (expiresAt is int) {
      payload[_expiresAtKey] = expiresAt;
    } else if (expiresAt is num) {
      payload[_expiresAtKey] = expiresAt.round();
    }

    await _channel.invokeMethod<void>('saveStravaTokens', payload);
  }

  Future<Map<String, Object?>> _loadTokens() async {
    try {
      return await _channel.invokeMapMethod<String, Object?>(
            'loadStravaTokens',
          ) ??
          {};
    } on MissingPluginException {
      return {};
    }
  }

  String? get _configurationError {
    if (_clientId.isEmpty || _clientSecret.isEmpty) {
      return 'Build Quantivita with STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET dart-defines first.';
    }
    if (!RegExp(r'^\d+$').hasMatch(_clientId)) {
      return 'STRAVA_CLIENT_ID must be the numeric Client ID from Strava, not the client secret or token.';
    }
    final redirectUri = Uri.tryParse(_redirectUri);
    if (redirectUri == null ||
        redirectUri.scheme != 'quantivita' ||
        redirectUri.host.isEmpty) {
      return 'STRAVA_REDIRECT_URI must look like quantivita://your-callback-domain/strava-auth.';
    }
    return null;
  }

  String _csv(MergedWorkoutPreview preview) {
    final rows = <List<Object?>>[
      ['section', 'field', 'value'],
      ['summary', 'title', preview.title],
      ['summary', 'export_type', preview.exportTypeLabel],
      ['summary', 'start_epoch', preview.startTime],
      ['summary', 'end_epoch', preview.endTime],
      ['summary', 'moving_minutes', preview.movingMinutes],
      ['summary', 'elapsed_minutes', preview.elapsedMinutes],
      ['summary', 'transition_minutes', preview.transitionMinutes],
      ['summary', 'active_energy_kcal', preview.energyKcal],
      ['summary', 'total_energy_kcal', preview.totalEnergyKcal],
      ['summary', 'distance_meters', preview.distanceMeters],
      ['summary', 'elevation_gain_meters', preview.elevationGainMeters],
      ['summary', 'average_speed_kmh', preview.averageSpeedKmh],
      ['summary', 'average_heart_rate', preview.averageHeartRate],
      ['summary', 'max_heart_rate', preview.maxHeartRate],
      ['summary', 'average_temperature_c', preview.averageTemperatureC],
      ['summary', 'average_humidity_percent', preview.averageHumidityPercent],
      ['summary', 'weather_conditions', preview.weatherConditions],
      ['summary', 'average_air_quality_index', preview.averageAirQualityIndex],
      ['summary', 'route_segments', preview.routeSegments],
      [],
      [
        'segment_index',
        'title',
        'source_uuid',
        'start_epoch',
        'end_epoch',
        'duration_minutes',
        'active_energy_kcal',
        'total_energy_kcal',
        'distance_meters',
        'elevation_gain_meters',
        'average_heart_rate',
        'max_heart_rate',
        'temperature_c',
        'humidity_percent',
        'weather_condition',
        'air_quality_index',
        'type_code',
        'has_route',
      ],
      for (var index = 0; index < preview.events.length; index++)
        [
          index + 1,
          preview.events[index].title,
          preview.events[index].sourceUuid,
          preview.events[index].startTime,
          preview.events[index].endTime,
          preview.events[index].durationMinutes,
          preview.events[index].energyKcal,
          preview.events[index].totalEnergyKcal,
          preview.events[index].distanceMeters,
          preview.events[index].elevationGainMeters,
          preview.events[index].averageHeartRate,
          preview.events[index].maxHeartRate,
          preview.events[index].temperatureC,
          preview.events[index].humidityPercent,
          preview.events[index].weatherCondition,
          preview.events[index].airQualityIndex,
          preview.events[index].typeCode,
          preview.events[index].hasRoute,
        ],
    ];

    return rows.map((row) => row.map(_csvCell).join(',')).join('\n');
  }

  String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    if (!text.contains(',') &&
        !text.contains('"') &&
        !text.contains('\n') &&
        !text.contains('\r')) {
      return text;
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  String _safeFileName(String text) {
    final safe = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return safe.isEmpty ? 'merged-workout' : safe;
  }
}

class _TokenResult {
  const _TokenResult({required this.success, this.token, this.message});

  final bool success;
  final String? token;
  final String? message;
}
