import 'package:flutter/material.dart';

import '../../../theme/quantivita_colors.dart';
import '../../../widgets/blurred_block.dart';
import '../../../widgets/panel.dart';

class HealthDataPlaceholder extends StatelessWidget {
  const HealthDataPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Panel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: QuantivitaColors.recovery.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: QuantivitaColors.recovery,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Waiting for real health data',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Once Apple Health data is available, these blocks will resolve into recovery, sleep, strain, and trend insights.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              const BlurredBlock(height: 118),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.15,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            _PlaceholderMetric(title: 'Recovery'),
            _PlaceholderMetric(title: 'Sleep'),
            _PlaceholderMetric(title: 'Strain'),
            _PlaceholderMetric(title: 'Stress'),
          ],
        ),
        const SizedBox(height: 14),
        const Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BlurredBlock(width: 140, height: 18),
              SizedBox(height: 18),
              BlurredBlock(height: 126),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaceholderMetric extends StatelessWidget {
  const _PlaceholderMetric({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const Spacer(),
          const BlurredBlock(width: 74, height: 34),
          const SizedBox(height: 10),
          const BlurredBlock(height: 28),
        ],
      ),
    );
  }
}
