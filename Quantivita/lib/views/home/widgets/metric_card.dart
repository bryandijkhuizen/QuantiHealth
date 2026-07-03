import 'package:flutter/material.dart';

import '../../../models/metric_model.dart';
import '../../../widgets/panel.dart';
import '../../../widgets/sparkline.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({required this.metric, required this.onTap, super.key});

  final MetricModel metric;
  final ValueChanged<MetricModel> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: '${metric.title} details',
        child: InkWell(
          onTap: () => onTap(metric),
          borderRadius: BorderRadius.circular(18),
          child: Panel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: metric.color.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(metric.icon, color: metric.color, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        metric.title.toUpperCase(),
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    Icon(
                      Icons.north_east_rounded,
                      size: 17,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          metric.value,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                    if (metric.unit.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          metric.unit,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: Sparkline(values: metric.samples, color: metric.color),
                ),
                const SizedBox(height: 8),
                Text(metric.caption, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
