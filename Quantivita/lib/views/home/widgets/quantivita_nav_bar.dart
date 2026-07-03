import 'package:flutter/material.dart';
import 'dart:ui';

class QuantivitaNavBar extends StatelessWidget {
  const QuantivitaNavBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.today_rounded, 'Today'),
      (Icons.monitor_heart_rounded, 'Trends'),
      (Icons.fitness_center_rounded, 'Log'),
      (Icons.person_rounded, 'You'),
    ];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(
                alpha: isDark ? 0.72 : 0.82,
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.84),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.10),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Tooltip(
                      message: items[i].$2,
                      child: InkWell(
                        onTap: () => onSelected(i),
                        borderRadius: BorderRadius.circular(24),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 58,
                          decoration: BoxDecoration(
                            color: selectedIndex == i
                                ? theme.colorScheme.onSurface.withValues(
                                    alpha: isDark ? 0.92 : 0.08,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                items[i].$1,
                                color: selectedIndex == i
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                items[i].$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: selectedIndex == i
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
