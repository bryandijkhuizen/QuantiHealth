import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/fitness_summary.dart';

class WorkoutExportResult {
  const WorkoutExportResult({
    required this.success,
    required this.message,
    this.filePath,
  });

  final bool success;
  final String message;
  final String? filePath;
}

class WorkoutExportService {
  static const _channel = MethodChannel('quantivita/healthkit');

  Future<WorkoutExportResult> exportMergedWorkout(
    MergedWorkoutPreview preview,
  ) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'exportMergedWorkout',
        _payload(preview),
      );

      return WorkoutExportResult(
        success: response?['success'] == true,
        message:
            response?['message'] as String? ??
            'Merged workout export completed.',
      );
    } on PlatformException catch (error) {
      return WorkoutExportResult(
        success: false,
        message: error.message ?? 'Merged workout export failed.',
      );
    } on MissingPluginException {
      return const WorkoutExportResult(
        success: false,
        message: 'Apple Health export is only available on iPhone.',
      );
    }
  }

  Future<WorkoutExportResult> shareStravaTcx(
    MergedWorkoutPreview preview,
  ) async {
    final result = await createStravaTcx(preview);
    if (!result.success || result.filePath == null) {
      return result;
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(result.filePath!, mimeType: 'application/vnd.garmin.tcx+xml'),
          ],
          subject: preview.title,
          text: 'Upload this Quantivita merged workout to Strava.',
        ),
      );

      return result;
    } catch (error) {
      return WorkoutExportResult(
        success: false,
        message: 'Strava TCX export failed: $error',
      );
    }
  }

  Future<WorkoutExportResult> createStravaTcx(
    MergedWorkoutPreview preview,
  ) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'createStravaTcx',
        _payload(preview),
      );
      final path = response?['path'] as String?;
      if (path == null || path.isEmpty) {
        return const WorkoutExportResult(
          success: false,
          message: 'Strava TCX could not be created.',
        );
      }

      return WorkoutExportResult(
        success: response?['success'] == true,
        message:
            response?['message'] as String? ?? 'Strava TCX is ready to share.',
        filePath: path,
      );
    } on PlatformException catch (error) {
      return WorkoutExportResult(
        success: false,
        message: error.message ?? 'Strava TCX export failed.',
      );
    } on MissingPluginException {
      return const WorkoutExportResult(
        success: false,
        message: 'Strava TCX export is only available on iPhone.',
      );
    }
  }

  Map<String, Object?> _payload(MergedWorkoutPreview preview) {
    return {
      'title': preview.title,
      'exportType': preview.exportTypeLabel,
      'startTime': preview.startTime,
      'endTime': preview.endTime,
      'movingMinutes': preview.movingMinutes,
      'elapsedMinutes': preview.elapsedMinutes,
      'activeEnergyKcal': preview.energyKcal,
      'totalEnergyKcal': preview.totalEnergyKcal,
      'distanceMeters': preview.distanceMeters,
      'elevationGainMeters': preview.elevationGainMeters,
      'averageSpeedKmh': preview.averageSpeedKmh,
      'averageHeartRate': preview.averageHeartRate,
      'maxHeartRate': preview.maxHeartRate,
      'averageTemperatureC': preview.averageTemperatureC,
      'averageHumidityPercent': preview.averageHumidityPercent,
      'weatherConditions': preview.weatherConditions,
      'averageAirQualityIndex': preview.averageAirQualityIndex,
      'routeSegments': preview.routeSegments,
      'segments': [
        for (final event in preview.events)
          {
            'title': event.title,
            'sourceUuid': event.sourceUuid,
            'startTime': event.startTime,
            'endTime': event.endTime,
            'durationMinutes': event.durationMinutes,
            'activeEnergyKcal': event.energyKcal,
            'totalEnergyKcal': event.totalEnergyKcal,
            'distanceMeters': event.distanceMeters,
            'elevationGainMeters': event.elevationGainMeters,
            'averageHeartRate': event.averageHeartRate,
            'maxHeartRate': event.maxHeartRate,
            'temperatureC': event.temperatureC,
            'humidityPercent': event.humidityPercent,
            'weatherCondition': event.weatherCondition,
            'airQualityIndex': event.airQualityIndex,
            'typeCode': event.typeCode,
            'hasRoute': event.hasRoute,
          },
      ],
    };
  }
}
