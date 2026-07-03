import 'package:flutter/material.dart';

import '../../widgets/panel.dart';
import '../../widgets/sparkline.dart';

class BiomarkerDetailPage extends StatelessWidget {
  const BiomarkerDetailPage({
    required this.title,
    required this.value,
    required this.range,
    required this.description,
    required this.insight,
    required this.icon,
    required this.color,
    required this.samples,
    super.key,
  });

  final String title;
  final String value;
  final String range;
  final String description;
  final String insight;
  final IconData icon;
  final Color color;
  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Spacer(),
                    IconButton.filledTonal(
                      onPressed: () {},
                      icon: const Icon(Icons.info_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
              sliver: SliverList.list(
                children: [
                  _Header(
                    title: title,
                    value: value,
                    range: range,
                    icon: icon,
                    color: color,
                    samples: samples,
                  ),
                  const SizedBox(height: 14),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What this means',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Insight',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          insight,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.value,
    required this.range,
    required this.icon,
    required this.color,
    required this.samples,
  });

  final String title;
  final String value;
  final String range;
  final IconData icon;
  final Color color;
  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(range, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(value, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: Sparkline(values: samples, color: color),
          ),
        ],
      ),
    );
  }
}
