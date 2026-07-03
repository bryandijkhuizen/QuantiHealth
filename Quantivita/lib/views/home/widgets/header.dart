import 'package:flutter/material.dart';

import '../../../theme/quantivita_colors.dart';

class Header extends StatelessWidget {
  const Header({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Spacer(),
              _HeaderPill(
                icon: Icons.check_circle_rounded,
                label: 'Sync complete',
                color: QuantivitaColors.recovery,
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: () {},
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () {},
                tooltip: 'Settings',
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Today, ${now.day} ${months[now.month - 1]}',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 36,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.76
                        : 0.86,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.14
                          : 0.82,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.24
                            : 0.08,
                      ),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Image.asset('lib/assets/icon.png'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
