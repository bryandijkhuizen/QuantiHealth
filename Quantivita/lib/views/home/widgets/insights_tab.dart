import 'package:flutter/material.dart';

import '../../../models/dashboard_snapshot.dart';
import '../../../models/personal_profile.dart';
import '../../../models/sleep_summary.dart';
import '../../../theme/quantivita_colors.dart';
import '../../../widgets/panel.dart';

class InsightsTab extends StatelessWidget {
  const InsightsTab({
    required this.snapshot,
    required this.profile,
    required this.sleepSummary,
    super.key,
  });

  final DashboardSnapshot snapshot;
  final PersonalProfile profile;
  final SleepSummary sleepSummary;

  @override
  Widget build(BuildContext context) {
    final insights = [
      (
        Icons.health_and_safety_rounded,
        'Today readiness',
        _personalizedReadiness(),
        QuantivitaColors.sleep,
      ),
      (
        Icons.favorite_rounded,
        'Biomarker check',
        'HRV ${snapshot.hrvDelta}, RHR ${snapshot.restingHeartRate}, RR ${snapshot.respiratoryRate}, SpO2 ${snapshot.oxygenSaturation}.',
        QuantivitaColors.recovery,
      ),
      (
        Icons.bedtime_rounded,
        'Sleep quality',
        '${sleepSummary.formatMinutes(sleepSummary.totalMinutes)} recorded. Quality ${sleepSummary.qualityScore}% with ${sleepSummary.formatMinutes(sleepSummary.deepMinutes)} deep and ${sleepSummary.formatMinutes(sleepSummary.remMinutes)} REM.',
        QuantivitaColors.sleep,
      ),
      (
        Icons.device_thermostat_rounded,
        'Temperature baseline',
        'Base temperature ${snapshot.baseTemperature}; sleeping wrist temperature ${snapshot.wristTemperature}. Watch deviations before hard training.',
        QuantivitaColors.strain,
      ),
      (
        Icons.lock_rounded,
        'Local-first',
        'Insights are calculated on-device from Apple Health data. No cloud database is used.',
        QuantivitaColors.strain,
      ),
    ];

    return Column(
      children: [
        for (final insight in insights) ...[
          Panel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: insight.$4.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(insight.$1, color: insight.$4),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insight.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        insight.$3,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (insight != insights.last) const SizedBox(height: 12),
        ],
      ],
    );
  }

  String _personalizedReadiness() {
    final ageText = profile.age > 0 ? ' for age ${profile.age}' : '';
    final bodyText = profile.bodyFatPercent > 0
        ? ' Body-fat context is available for trend interpretation.'
        : '';
    return '${snapshot.recoverySummary}$ageText.$bodyText';
  }
}
