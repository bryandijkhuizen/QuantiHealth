import 'package:flutter/material.dart';

import '../../../models/metric_model.dart';
import 'metric_card.dart';

class MetricsGrid extends StatelessWidget {
  const MetricsGrid({
    required this.metrics,
    required this.onMetricTap,
    super.key,
  });

  final List<MetricModel> metrics;
  final ValueChanged<MetricModel> onMetricTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useOneColumn = constraints.maxWidth < 360;
        final cards = metrics
            .map((metric) => MetricCard(metric: metric, onTap: onMetricTap))
            .toList();

        if (useOneColumn) {
          return Column(
            children: [
              for (final card in cards) ...[
                card,
                if (card != cards.last) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 10),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 10),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        );
      },
    );
  }
}
