import 'package:flutter/material.dart';

import '../../../models/dashboard_snapshot.dart';
import '../../../theme/quantivita_colors.dart';

class HealthMonitorPanel extends StatelessWidget {
  const HealthMonitorPanel({required this.snapshot, super.key});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MonitorMetric(
        icon: Icons.air_rounded,
        label: 'RR',
        value: snapshot.respiratoryRate,
        range: const _MetricRange(
          min: 12,
          normalMin: 12,
          normalMax: 20,
          max: 24,
        ),
        fallbackUnit: 'rpm',
        normalLabel: 'Normal',
      ),
      _MonitorMetric(
        icon: Icons.favorite_rounded,
        label: 'RHR',
        value: snapshot.restingHeartRate,
        range: const _MetricRange(
          min: 40,
          normalMin: 45,
          normalMax: 75,
          max: 100,
        ),
        fallbackUnit: 'bpm',
        normalLabel: 'Normal',
      ),
      _MonitorMetric(
        icon: Icons.monitor_heart_rounded,
        label: 'HRV',
        value: snapshot.hrvDelta,
        range: const _MetricRange(
          min: 20,
          normalMin: 35,
          normalMax: 90,
          max: 120,
        ),
        fallbackUnit: 'ms',
        normalLabel: 'Normal',
      ),
      _MonitorMetric(
        icon: Icons.water_drop_rounded,
        label: 'SpO2',
        value: snapshot.oxygenSaturation,
        range: const _MetricRange(
          min: 88,
          normalMin: 95,
          normalMax: 100,
          max: 100,
        ),
        fallbackUnit: '%',
        normalLabel: 'Normal',
      ),
      _MonitorMetric(
        icon: Icons.device_thermostat_rounded,
        label: 'Temp',
        value: snapshot.wristTemperature,
        range: const _MetricRange(
          min: 35.0,
          normalMin: 35.8,
          normalMax: 37.5,
          max: 38.5,
        ),
        fallbackUnit: '°C',
        normalLabel: 'Normal',
      ),
      _MonitorMetric(
        icon: Icons.bed_rounded,
        label: 'Sleep',
        value: snapshot.sleepDuration,
        range: const _MetricRange(
          min: 240,
          normalMin: 420,
          normalMax: 540,
          max: 660,
        ),
        fallbackUnit: '',
        normalLabel: 'Normal',
        color: QuantivitaColors.sleep,
        parser: _parseSleepMinutes,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'Health Monitor',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          itemCount: items.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.28,
          ),
          itemBuilder: (context, index) => _MonitorCard(metric: items[index]),
        ),
      ],
    );
  }
}

class _MonitorCard extends StatelessWidget {
  const _MonitorCard({required this.metric});

  final _MonitorMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = metric.parsedValue;
    final status = metric.status;
    final color = status.color ?? metric.color ?? theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.07),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      metric.icon,
                      size: 22,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.28,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        metric.label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.52,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      text: metric.displayValue,
                      children: [
                        if (metric.displayUnit.isNotEmpty)
                          TextSpan(
                            text: ' ${metric.displayUnit}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.48,
                              ),
                            ),
                          ),
                      ],
                    ),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontSize: 35,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(status.icon, size: 18, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        parsed == null ? 'No data' : status.label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _VerticalRangeIndicator(
            position: metric.position,
            color: color,
            hasData: parsed != null,
          ),
        ],
      ),
    );
  }
}

class _VerticalRangeIndicator extends StatelessWidget {
  const _VerticalRangeIndicator({
    required this.position,
    required this.color,
    required this.hasData,
  });

  final double position;
  final Color color;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.10);
    return SizedBox(
      width: 34,
      height: 94,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 30,
            decoration: BoxDecoration(
              color: muted,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Positioned(
            top: 14,
            bottom: 14,
            child: Container(
              width: 10,
              decoration: BoxDecoration(
                color: hasData ? color.withValues(alpha: 0.72) : muted,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(top: 7, child: _RailTick(color: hasData ? color : muted)),
          Positioned(
            bottom: 7,
            child: _RailTick(color: hasData ? color : muted),
          ),
          Positioned(
            top: 14 + (1 - position.clamp(0, 1)) * 66,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: hasData ? 0.42 : 0),
                    blurRadius: 12,
                  ),
                ],
                border: Border.all(color: hasData ? color : muted, width: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailTick extends StatelessWidget {
  const _RailTick({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 5,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _MonitorMetric {
  const _MonitorMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.range,
    required this.fallbackUnit,
    required this.normalLabel,
    this.color,
    this.parser = _parseLeadingDouble,
  });

  final IconData icon;
  final String label;
  final String value;
  final _MetricRange range;
  final String fallbackUnit;
  final String normalLabel;
  final Color? color;
  final double? Function(String value) parser;

  double? get parsedValue => parser(value);

  String get displayValue {
    if (value.startsWith('No ') || value == '-') return '--';
    if (label == 'Sleep') return value;
    final parsed = parsedValue;
    if (parsed == null) return '--';
    return parsed.toStringAsFixed(parsed.truncateToDouble() == parsed ? 0 : 1);
  }

  String get displayUnit {
    if (label == 'Sleep') return '';
    final unit = value
        .replaceFirst(RegExp(r'^[0-9]+([.,][0-9]+)?\s*'), '')
        .trim();
    return unit.isEmpty || unit.startsWith('No') ? fallbackUnit : unit;
  }

  double get position {
    final parsed = parsedValue;
    if (parsed == null) return 0.5;
    return ((parsed - range.min) / (range.max - range.min)).clamp(0, 1);
  }

  _MonitorStatus get status {
    final parsed = parsedValue;
    if (parsed == null) return _MonitorStatus.noData;
    if (parsed < range.normalMin) {
      return _MonitorStatus.low;
    }
    if (parsed > range.normalMax) {
      return _MonitorStatus.high;
    }
    return _MonitorStatus.normal(normalLabel);
  }
}

class _MetricRange {
  const _MetricRange({
    required this.min,
    required this.normalMin,
    required this.normalMax,
    required this.max,
  });

  final double min;
  final double normalMin;
  final double normalMax;
  final double max;
}

class _MonitorStatus {
  const _MonitorStatus({required this.label, required this.icon, this.color});

  factory _MonitorStatus.normal(String label) {
    return _MonitorStatus(
      label: label,
      icon: Icons.check_circle_rounded,
      color: QuantivitaColors.recovery,
    );
  }

  static const high = _MonitorStatus(
    label: 'Higher',
    icon: Icons.arrow_circle_up_rounded,
    color: QuantivitaColors.strain,
  );

  static const low = _MonitorStatus(
    label: 'Lower',
    icon: Icons.arrow_circle_down_rounded,
    color: QuantivitaColors.sleep,
  );

  static const noData = _MonitorStatus(
    label: 'No data',
    icon: Icons.help_rounded,
  );

  final String label;
  final IconData icon;
  final Color? color;
}

double? _parseLeadingDouble(String value) {
  final match = RegExp(r'([0-9]+([.,][0-9]+)?)').firstMatch(value);
  return double.tryParse(match?.group(1)?.replaceAll(',', '.') ?? '');
}

double? _parseSleepMinutes(String value) {
  final match = RegExp(r'([0-9]+)h\s*([0-9]+)m').firstMatch(value);
  if (match == null) return null;
  final hours = double.tryParse(match.group(1) ?? '') ?? 0;
  final minutes = double.tryParse(match.group(2) ?? '') ?? 0;
  return hours * 60 + minutes;
}
