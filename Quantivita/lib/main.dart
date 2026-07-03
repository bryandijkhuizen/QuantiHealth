import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/observability_service.dart';

void main() {
  final startup = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      ObservabilityService.instance.error(
        'uncaught_flutter_error',
        details.exceptionAsString(),
        errorCode: 'QV-APP-001',
        metadata: {'library': details.library ?? 'flutter'},
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      ObservabilityService.instance.error(
        'uncaught_platform_error',
        error.toString(),
        errorCode: 'QV-APP-001',
      ),
    );
    return false;
  };
  runApp(const QuantivitaApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      ObservabilityService.instance.info(
        'app_startup_completed',
        'Quantivita app startup completed',
        errorCode: startup.elapsedMilliseconds > 2000 ? 'QV-PERF-001' : null,
        durationMs: startup.elapsedMilliseconds,
      ),
    );
  });
}
