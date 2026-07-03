import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/dashboard_snapshot.dart';
import '../../../theme/quantivita_colors.dart';
import '../../../widgets/panel.dart';

class NutritionPanel extends StatelessWidget {
  const NutritionPanel({required this.snapshot, super.key});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaten = snapshot.dietaryEnergyKcal.round();
    final burned = snapshot.totalBurnedEnergyKcal.round();
    final active = snapshot.activeEnergyKcal.round();
    final resting = snapshot.basalEnergyKcal.round();
    final net = snapshot.netEnergyKcal.round();
    final balance = net > 75
        ? 'Surplus'
        : net < -75
        ? 'Deficit'
        : 'Balanced';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text('Nutrition', style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 12),
        Panel(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Today's foods",
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.72,
                        ),
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      '${_formatInt(eaten)} kcal',
                      style: theme.textTheme.displaySmall,
                    ),
                  ),
                  _EnergyLegend(
                    icon: Icons.local_fire_department_rounded,
                    value: _formatInt(burned),
                    color: QuantivitaColors.strain,
                  ),
                  const SizedBox(width: 12),
                  _EnergyLegend(
                    icon: Icons.restaurant_rounded,
                    value: _formatInt(eaten),
                    color: QuantivitaColors.stress,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _NetEnergyGauge(value: net),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MiniNutritionStat(
                      label: 'Active',
                      value: '${_formatInt(active)} kcal',
                      color: QuantivitaColors.strain,
                    ),
                  ),
                  Expanded(
                    child: _MiniNutritionStat(
                      label: 'Resting',
                      value: '${_formatInt(resting)} kcal',
                      color: QuantivitaColors.sleep,
                    ),
                  ),
                  Expanded(
                    child: _MiniNutritionStat(
                      label: 'Net',
                      value: '${net > 0 ? '+' : ''}${_formatInt(net)}',
                      color: net > 0
                          ? QuantivitaColors.stress
                          : QuantivitaColors.activity,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MacroPill(
                    label: 'Carbs',
                    value: snapshot.dietaryCarbohydratesG,
                    color: QuantivitaColors.strain,
                  ),
                  const SizedBox(width: 8),
                  _MacroPill(
                    label: 'Protein',
                    value: snapshot.dietaryProteinG,
                    color: QuantivitaColors.activity,
                  ),
                  const SizedBox(width: 8),
                  _MacroPill(
                    label: 'Fat',
                    value: snapshot.dietaryFatG,
                    color: QuantivitaColors.stress,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _HydrationBlock(
                currentMl: snapshot.dietaryWaterMl,
                targetMl: snapshot.waterTargetMl,
                baseTargetMl: snapshot.waterBaseTargetMl,
                activityExtraMl: snapshot.waterActivityExtraMl,
                workoutExtraMl: snapshot.waterWorkoutExtraMl,
              ),
              const SizedBox(height: 10),
              Text(
                '$balance today: eaten kcal minus active and resting burn.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatInt(num value) {
    final rounded = value.round();
    final sign = rounded < 0 ? '-' : '';
    final digits = rounded.abs().toString();
    final buffer = StringBuffer(sign);
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

class _HydrationBlock extends StatelessWidget {
  const _HydrationBlock({
    required this.currentMl,
    required this.targetMl,
    required this.baseTargetMl,
    required this.activityExtraMl,
    required this.workoutExtraMl,
  });

  final double currentMl;
  final double targetMl;
  final double baseTargetMl;
  final double activityExtraMl;
  final double workoutExtraMl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = targetMl <= 0
        ? 0.0
        : (currentMl / targetMl).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: QuantivitaColors.sleep.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: QuantivitaColors.sleep.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: QuantivitaColors.sleep.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.water_drop_rounded,
                  color: QuantivitaColors.sleep,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hydration', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      '${_liters(currentMl)} / ${_liters(targetMl)} target',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: QuantivitaColors.sleep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.9),
              valueColor: const AlwaysStoppedAnimation<Color>(
                QuantivitaColors.sleep,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_explanation, style: theme.textTheme.labelMedium),
          ),
        ],
      ),
    );
  }

  String _liters(double ml) {
    return '${(ml / 1000).toStringAsFixed(1)} L';
  }

  String get _explanation {
    final extra = activityExtraMl + workoutExtraMl;
    if (extra < 50) {
      return 'Target starts from body size: ${_liters(baseTargetMl)} baseline today.';
    }

    return 'Target is ${_liters(baseTargetMl)} baseline + ${_liters(extra)} extra from movement and workouts, because training and active kcal increase fluid needs.';
  }
}

class _NetEnergyGauge extends StatelessWidget {
  const _NetEnergyGauge({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    const min = -500.0;
    const max = 500.0;
    final normalized = ((value.clamp(min, max) - min) / (max - min)).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final markerX = math.max(8.0, math.min(width - 8, width * normalized));
        return SizedBox(
          height: 76,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 8,
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: QuantivitaColors.stress.withValues(alpha: 0.22),
                        blurRadius: 12,
                      ),
                    ],
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF4B2C),
                        Color(0xFFF0A43A),
                        Color(0xFFE8F4E6),
                        Color(0xFF8EB7FF),
                        Color(0xFF6D45E8),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: markerX - 13,
                top: 0,
                child: Container(
                  width: 26,
                  height: 30,
                  alignment: Alignment.center,
                  child: Text(
                    value == 0 ? '0' : '',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: markerX - 8,
                top: 3,
                child: Container(
                  width: 16,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 22,
                child: Container(
                  height: 1,
                  color: Theme.of(context).dividerColor,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    _GaugeTick('-500'),
                    _GaugeTick('-250'),
                    _GaugeTick('0'),
                    _GaugeTick('250'),
                    _GaugeTick('500'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GaugeTick extends StatelessWidget {
  const _GaugeTick(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.labelMedium);
  }
}

class _EnergyLegend extends StatelessWidget {
  const _EnergyLegend({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _MiniNutritionStat extends StatelessWidget {
  const _MiniNutritionStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _MacroPill extends StatelessWidget {
  const _MacroPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Text(
          '$label ${value.round()}g',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
