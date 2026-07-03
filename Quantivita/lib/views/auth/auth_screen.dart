import 'package:flutter/material.dart';

import '../../theme/quantivita_colors.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({
    required this.isLoading,
    required this.onAppleSignIn,
    required this.onContinueOffline,
    super.key,
  });

  final bool isLoading;
  final VoidCallback onAppleSignIn;
  final VoidCallback onContinueOffline;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: QuantivitaColors.recovery,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.monitor_heart_rounded,
                color: QuantivitaColors.onAccent,
                size: 30,
              ),
            ),
            const SizedBox(height: 24),
            Text('Quantivita', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 12),
            Text(
              'Sign in with Apple to keep your health companion tied to you, not to a hosted database.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: isLoading ? null : onAppleSignIn,
                icon: const Icon(Icons.apple_rounded),
                label: Text(
                  isLoading ? 'Opening Apple...' : 'Continue with Apple',
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: isLoading ? null : onContinueOffline,
                icon: const Icon(Icons.cloud_off_rounded),
                label: const Text('Continue offline'),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Health data stays local first. iCloud sync is only used through your private Apple container.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}
