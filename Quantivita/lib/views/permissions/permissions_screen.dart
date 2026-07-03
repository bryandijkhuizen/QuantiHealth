import 'package:flutter/material.dart';

import '../../theme/quantivita_colors.dart';
import '../../widgets/panel.dart';

class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({
    required this.isLoading,
    required this.onAllowHealth,
    super.key,
  });

  final bool isLoading;
  final VoidCallback onAllowHealth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect Apple Health',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Quantivita needs permission before it can calculate recovery, sleep, strain, and trends.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            const Panel(
              child: Column(
                children: [
                  _PermissionRow(
                    icon: Icons.bedtime_rounded,
                    title: 'Sleep',
                    body: 'Sleep duration, consistency, and debt.',
                  ),
                  SizedBox(height: 14),
                  _PermissionRow(
                    icon: Icons.monitor_heart_rounded,
                    title: 'Heart signals',
                    body: 'HRV and resting heart rate for recovery.',
                  ),
                  SizedBox(height: 14),
                  _PermissionRow(
                    icon: Icons.fitness_center_rounded,
                    title: 'Activity',
                    body: 'Workouts, steps, active energy, and load.',
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: isLoading ? null : onAllowHealth,
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.favorite_rounded),
                label: Text(
                  isLoading
                      ? 'Opening Apple Health...'
                      : 'Allow Apple Health access',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You can change these permissions later in the iOS Health app.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: QuantivitaColors.sleep.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: QuantivitaColors.sleep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(body, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
