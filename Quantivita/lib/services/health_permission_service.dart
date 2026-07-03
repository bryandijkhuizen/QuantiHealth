import 'package:flutter/services.dart';

enum HealthPermissionStatus { connected, noData, unavailable, denied, failed }

class HealthPermissionResult {
  const HealthPermissionResult({
    required this.status,
    required this.message,
    this.summary = const {},
    this.textSummary = const {},
  });

  final HealthPermissionStatus status;
  final String message;
  final Map<String, double> summary;
  final Map<String, String> textSummary;
}

class HealthPermissionService {
  static const _channel = MethodChannel('quantivita/healthkit');

  Future<HealthPermissionResult> requestAuthorization() async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'requestAuthorization',
      );

      final available = response?['available'] == true;
      final authorized = response?['authorized'] == true;
      final hasRecentData = response?['hasRecentData'] == true;
      final summary = _parseSummary(response?['summary']);
      final textSummary = _parseTextSummary(response?['summary']);
      final message =
          response?['message'] as String? ?? 'Apple Health status is unknown.';

      if (!available) {
        return HealthPermissionResult(
          status: HealthPermissionStatus.unavailable,
          message: message,
          textSummary: textSummary,
        );
      }

      if (!authorized) {
        return HealthPermissionResult(
          status: HealthPermissionStatus.denied,
          message: message,
          textSummary: textSummary,
        );
      }

      if (!hasRecentData) {
        return HealthPermissionResult(
          status: HealthPermissionStatus.noData,
          message: message,
          summary: summary,
          textSummary: textSummary,
        );
      }

      return HealthPermissionResult(
        status: HealthPermissionStatus.connected,
        message: message,
        summary: summary,
        textSummary: textSummary,
      );
    } on PlatformException catch (error) {
      return HealthPermissionResult(
        status: HealthPermissionStatus.failed,
        message: error.message ?? 'Apple Health permission failed.',
      );
    } on MissingPluginException {
      return const HealthPermissionResult(
        status: HealthPermissionStatus.unavailable,
        message: 'Apple Health is only available on iPhone.',
      );
    }
  }

  Future<HealthPermissionResult> loadWorkoutHistory(int days) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'loadWorkoutHistory',
        {'days': days},
      );

      final summary = _parseSummary(response?['summary']);
      final textSummary = _parseTextSummary(response?['summary']);
      final message =
          response?['message'] as String? ?? 'Workout history updated.';

      return HealthPermissionResult(
        status: HealthPermissionStatus.connected,
        message: message,
        summary: summary,
        textSummary: textSummary,
      );
    } on PlatformException catch (error) {
      return HealthPermissionResult(
        status: HealthPermissionStatus.failed,
        message: error.message ?? 'Workout history failed.',
      );
    } on MissingPluginException {
      return const HealthPermissionResult(
        status: HealthPermissionStatus.unavailable,
        message: 'Workout history is only available on iPhone.',
      );
    }
  }

  Map<String, double> _parseSummary(Object? value) {
    if (value is! Map) return const {};

    return value.map((key, rawValue) {
      final number = rawValue is num ? rawValue.toDouble() : 0.0;
      return MapEntry(key.toString(), number);
    });
  }

  Map<String, String> _parseTextSummary(Object? value) {
    if (value is! Map) return const {};

    return value.map((key, rawValue) {
      final text = rawValue is String ? rawValue : '';
      return MapEntry(key.toString(), text);
    })..removeWhere((_, value) => value.isEmpty);
  }
}
