import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'account_service.dart';

class ObservabilityService {
  ObservabilityService({AccountService? accountService})
    : _accountService = accountService ?? AccountService();

  static final ObservabilityService instance = ObservabilityService();
  static const _baseUrl = String.fromEnvironment(
    'QUANTIVITA_API_BASE_URL',
    defaultValue: 'https://api.quantivita.bryandijkh.com',
  );
  static const _environment = bool.fromEnvironment('dart.vm.product')
      ? 'production'
      : 'development';

  final AccountService _accountService;

  String newCorrelationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> info(
    String event,
    String message, {
    String? correlationId,
    String? errorCode,
    int? durationMs,
    Map<String, Object?> metadata = const {},
  }) => _send(
    'info',
    event,
    message,
    correlationId: correlationId,
    errorCode: errorCode,
    durationMs: durationMs,
    metadata: metadata,
  );

  Future<void> warn(
    String event,
    String message, {
    String? correlationId,
    String? errorCode,
    int? durationMs,
    Map<String, Object?> metadata = const {},
  }) => _send(
    'warn',
    event,
    message,
    correlationId: correlationId,
    errorCode: errorCode,
    durationMs: durationMs,
    metadata: metadata,
  );

  Future<void> error(
    String event,
    String message, {
    String? correlationId,
    String? errorCode,
    int? durationMs,
    Map<String, Object?> metadata = const {},
  }) => _send(
    'error',
    event,
    message,
    correlationId: correlationId,
    errorCode: errorCode,
    durationMs: durationMs,
    metadata: metadata,
  );

  Future<T> track<T>(
    String event,
    Future<T> Function() action, {
    required String slowCode,
    int warnAfterMs = 1000,
    String? correlationId,
    Map<String, Object?> metadata = const {},
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await action();
      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed >= warnAfterMs) {
        await warn(
          '${event}_slow',
          '$event was slow',
          correlationId: correlationId,
          errorCode: slowCode,
          durationMs: elapsed,
          metadata: metadata,
        );
      }
      return result;
    } catch (error) {
      await this.error(
        '${event}_failed',
        error.toString(),
        correlationId: correlationId,
        errorCode: 'QV-APP-001',
        durationMs: stopwatch.elapsedMilliseconds,
        metadata: metadata,
      );
      rethrow;
    }
  }

  Future<void> _send(
    String level,
    String event,
    String message, {
    String? correlationId,
    String? errorCode,
    int? durationMs,
    Map<String, Object?> metadata = const {},
  }) async {
    try {
      final account = await _accountService.loadAccount();
      if (account == null) return;
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final request = await client.postUrl(
        Uri.parse(
          '$_baseUrl/api/users/${account.accountId}/observability/logs',
        ),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${account.syncToken}',
      );
      request.write(
        jsonEncode({
          'level': level,
          'app': 'quantivita',
          'service': 'frontend',
          'environment': _environment,
          'event': event,
          'message': _safeMessage(message),
          'error_code': errorCode,
          'correlation_id': correlationId ?? newCorrelationId(),
          'duration_ms': durationMs,
          'metadata': _safeMetadata(metadata),
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      await response.drain<void>();
      client.close(force: true);
    } catch (_) {
      // Logging must never break the app.
    }
  }

  String _safeMessage(String value) {
    final redacted = value.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9._~+/-]+=*'),
      'Bearer [redacted]',
    );
    return redacted.substring(0, min(redacted.length, 300));
  }

  Map<String, Object?> _safeMetadata(Map<String, Object?> metadata) {
    final safe = <String, Object?>{};
    for (final entry in metadata.entries) {
      if (RegExp(
        r'token|secret|password|key|authorization|health|payload|body',
        caseSensitive: false,
      ).hasMatch(entry.key)) {
        continue;
      }
      final value = entry.value;
      if (value == null || value is String || value is num || value is bool) {
        safe[entry.key] = value?.toString();
      }
    }
    return safe;
  }
}
