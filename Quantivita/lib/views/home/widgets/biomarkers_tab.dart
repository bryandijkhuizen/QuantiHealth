import 'package:flutter/material.dart';

import '../../../models/dashboard_snapshot.dart';
import '../../../models/metric_model.dart';
import '../../../models/stress_monitor.dart';
import '../../../theme/quantivita_colors.dart';
import '../../details/biomarker_detail_page.dart';
import 'health_details_panel.dart';
import 'stress_monitor_panel.dart';

class BiomarkersTab extends StatelessWidget {
  const BiomarkersTab({
    required this.snapshot,
    required this.stressMonitor,
    required this.stressFilter,
    required this.onStressFilterChanged,
    required this.onMetricTap,
    super.key,
  });

  final DashboardSnapshot snapshot;
  final StressMonitor stressMonitor;
  final StressFilter stressFilter;
  final ValueChanged<StressFilter> onStressFilterChanged;
  final ValueChanged<MetricModel> onMetricTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _BiomarkerHeader(snapshot: snapshot),
        const SizedBox(height: 14),
        _BiomarkerGrid(snapshot: snapshot),
        const SizedBox(height: 14),
        StressMonitorPanel(
          monitor: stressMonitor,
          selectedFilter: stressFilter,
          onFilterChanged: onStressFilterChanged,
        ),
        const SizedBox(height: 14),
        HealthDetailsPanel(snapshot: snapshot, onMetricTap: onMetricTap),
      ],
    );
  }
}

class _BiomarkerGrid extends StatelessWidget {
  const _BiomarkerGrid({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final biomarkers = [
      _BiomarkerInfo(
        Icons.monitor_heart_rounded,
        'HRV',
        snapshot.hrvDelta,
        'Recovery signal',
        QuantivitaColors.sleep,
        'Higher is usually better for your own baseline, but HRV is highly individual.',
        'Compare HRV against your personal 30-60 day baseline rather than a population average. A drop can reflect stress, alcohol, illness, hard training, or poor sleep.',
        const [0.42, 0.46, 0.4, 0.55, 0.62, 0.58, 0.66],
      ),
      _BiomarkerInfo(
        Icons.favorite_rounded,
        'RHR',
        snapshot.restingHeartRate,
        'Resting heart',
        QuantivitaColors.stress,
        'Many adults sit around 60-100 bpm, but fit people can be lower.',
        'A higher-than-normal resting heart rate can point to fatigue, dehydration, stress, illness, or accumulated training load.',
        const [0.7, 0.64, 0.6, 0.58, 0.54, 0.56, 0.52],
      ),
      _BiomarkerInfo(
        Icons.air_rounded,
        'RR',
        snapshot.respiratoryRate,
        'Respiration',
        QuantivitaColors.recovery,
        'Typical adult resting respiratory rate is often about 12-20 breaths/min.',
        'Respiratory rate is useful as a stability signal. Sustained elevation versus your baseline can be a recovery or illness flag.',
        const [0.42, 0.44, 0.43, 0.47, 0.46, 0.45, 0.44],
      ),
      _BiomarkerInfo(
        Icons.water_drop_rounded,
        'SpO2',
        snapshot.oxygenSaturation,
        'Blood oxygen',
        QuantivitaColors.sleep,
        'Typical readings are often 95-100% at sea level.',
        'Low or unusual values can be noisy on wearables, but repeated dips deserve attention and context.',
        const [0.92, 0.96, 0.95, 0.97, 0.96, 0.98, 0.97],
      ),
      _BiomarkerInfo(
        Icons.device_thermostat_rounded,
        'Base temp',
        snapshot.baseTemperature,
        'Body temperature',
        QuantivitaColors.strain,
        'Normal body temperature varies by person and measurement method.',
        'Temperature is most useful as deviation from your own baseline. Elevation can reflect illness, cycle phase, poor recovery, or environment.',
        const [0.4, 0.42, 0.41, 0.46, 0.6, 0.52, 0.44],
      ),
      _BiomarkerInfo(
        Icons.watch_rounded,
        'Wrist temp',
        snapshot.wristTemperature,
        'Sleeping wrist',
        QuantivitaColors.activity,
        'Sleeping wrist temperature is mainly a baseline deviation signal.',
        'Apple Watch wrist temperature helps spot overnight deviations, which can improve recovery and wellness context.',
        const [0.38, 0.4, 0.42, 0.5, 0.54, 0.48, 0.44],
      ),
    ];

    return GridView.builder(
      itemCount: biomarkers.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.42,
      ),
      itemBuilder: (context, index) {
        final biomarker = biomarkers[index];
        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BiomarkerDetailPage(
                title: biomarker.title,
                value: biomarker.value,
                range: biomarker.range,
                description: biomarker.description,
                insight: biomarker.insight,
                icon: biomarker.icon,
                color: biomarker.color,
                samples: biomarker.samples,
              ),
            ),
          ),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(biomarker.icon, color: biomarker.color, size: 22),
                const Spacer(),
                Text(
                  biomarker.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  biomarker.title,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  biomarker.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BiomarkerInfo {
  const _BiomarkerInfo(
    this.icon,
    this.title,
    this.value,
    this.caption,
    this.color,
    this.range,
    this.description,
    this.samples,
  ) : insight = description;

  final IconData icon;
  final String title;
  final String value;
  final String caption;
  final Color color;
  final String range;
  final String description;
  final String insight;
  final List<double> samples;
}

class _BiomarkerHeader extends StatelessWidget {
  const _BiomarkerHeader({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite_rounded, color: QuantivitaColors.stress),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Biomarkers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'HRV ${snapshot.hrvDelta} • Sleep ${snapshot.sleepDuration}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
