import 'package:flutter/material.dart';

import '../../../models/fitness_summary.dart';
import '../../../models/personal_profile.dart';
import '../../../services/account_service.dart';
import '../../../services/progressa_integration_service.dart';
import '../../../services/strava_service.dart';
import '../../../theme/quantivita_colors.dart';
import '../../../widgets/panel.dart';

class PersonalizationTab extends StatefulWidget {
  const PersonalizationTab({
    required this.profile,
    required this.healthSummary,
    required this.fitnessSummary,
    required this.account,
    required this.onChanged,
    super.key,
  });

  final PersonalProfile profile;
  final Map<String, double> healthSummary;
  final FitnessSummary fitnessSummary;
  final QuantivitaAccount? account;
  final void Function({
    int? age,
    String? birthDate,
    String? biologicalSex,
    double? weightKg,
    double? heightCm,
    double? bodyFatPercent,
  })
  onChanged;

  @override
  State<PersonalizationTab> createState() => _PersonalizationTabState();
}

class _PersonalizationTabState extends State<PersonalizationTab> {
  final StravaService stravaService = StravaService();
  final ProgressaIntegrationService progressaIntegrationService =
      ProgressaIntegrationService();
  late final TextEditingController ageController;
  late final TextEditingController birthDateController;
  late final TextEditingController weightController;
  late final TextEditingController heightController;
  late final TextEditingController fatController;
  late String sex;
  bool isConnectingStrava = false;
  bool isConnectingProgressa = false;
  bool isStravaConnected = false;
  bool isProgressaConnected = false;
  String? integrationMessage;

  @override
  void initState() {
    super.initState();
    ageController = TextEditingController(
      text: widget.profile.age > 0 ? '${widget.profile.age}' : '',
    );
    birthDateController = TextEditingController(
      text: widget.profile.birthDate != 'Not set'
          ? widget.profile.birthDate
          : '',
    );
    weightController = TextEditingController(
      text: widget.profile.weightKg > 0
          ? widget.profile.weightKg.toStringAsFixed(1)
          : '',
    );
    heightController = TextEditingController(
      text: widget.profile.heightCm > 0
          ? widget.profile.heightCm.toStringAsFixed(0)
          : '',
    );
    fatController = TextEditingController(
      text: widget.profile.bodyFatPercent > 0
          ? widget.profile.bodyFatPercent.toStringAsFixed(1)
          : '',
    );
    sex = widget.profile.biologicalSex;
    _loadIntegrationStatuses();
  }

  Future<void> _loadIntegrationStatuses() async {
    final stravaConnected = await stravaService.isConnected();
    final progressaStatus = await progressaIntegrationService.isConnected();
    if (!mounted) return;
    setState(() {
      isStravaConnected = stravaConnected;
      isProgressaConnected = progressaStatus.connected == true;
    });
  }

  @override
  void dispose() {
    ageController.dispose();
    birthDateController.dispose();
    weightController.dispose();
    heightController.dispose();
    fatController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onChanged(
      age: int.tryParse(ageController.text),
      birthDate: birthDateController.text.trim().isEmpty
          ? null
          : birthDateController.text.trim(),
      biologicalSex: sex,
      weightKg: double.tryParse(weightController.text.replaceAll(',', '.')),
      heightCm: double.tryParse(heightController.text.replaceAll(',', '.')),
      bodyFatPercent: double.tryParse(fatController.text.replaceAll(',', '.')),
    );
    FocusScope.of(context).unfocus();
  }

  Future<void> _toggleStrava() async {
    if (isConnectingStrava) return;

    setState(() {
      isConnectingStrava = true;
      integrationMessage = null;
    });

    final result = isStravaConnected
        ? await stravaService.disconnect()
        : await stravaService.connect();
    if (!mounted) return;

    setState(() {
      isConnectingStrava = false;
      if (result.success) {
        isStravaConnected = !isStravaConnected;
      }
      integrationMessage = result.message;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _toggleProgressa() async {
    if (isConnectingProgressa) return;

    setState(() {
      isConnectingProgressa = true;
      integrationMessage = null;
    });

    final result = isProgressaConnected
        ? await progressaIntegrationService.disconnect()
        : await progressaIntegrationService.connect();
    if (!mounted) return;

    setState(() {
      isConnectingProgressa = false;
      if (result.success) {
        isProgressaConnected = !isProgressaConnected;
      }
      integrationMessage = result.message;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.person_rounded,
                    color: QuantivitaColors.recovery,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Personalisation',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Apple Health values are used first. Anything missing can be filled here and used in your analysis.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (widget.account != null) ...[
                const SizedBox(height: 12),
                _AccountBadge(account: widget.account!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.extension_rounded,
                    color: QuantivitaColors.sleep,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'App integrations',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _IntegrationRow(
                title: 'Strava',
                subtitle:
                    'Upload merged TCX workouts directly to Strava with activity:write.',
                icon: Icons.directions_run_rounded,
                statusLabel: isStravaConnected ? 'Connected' : 'Not connected',
                isConnected: isStravaConnected,
                isLoading: isConnectingStrava,
                onPressed: _toggleStrava,
              ),
              const Divider(height: 24),
              _IntegrationRow(
                title: 'Progressa',
                subtitle:
                    'Connect Progressa securely, then fetch strength workout details for the signed-in Quantivita user.',
                icon: Icons.fitness_center_rounded,
                statusLabel: isProgressaConnected
                    ? 'Connected'
                    : 'Not connected',
                isConnected: isProgressaConnected,
                isLoading: isConnectingProgressa,
                onPressed: _toggleProgressa,
              ),
              if (integrationMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  integrationMessage!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            children: [
              _InputRow(
                label: 'Age',
                value: widget.profile.age > 0
                    ? '${widget.profile.age}'
                    : 'Missing',
                controller: ageController,
                suffix: 'years',
                keyboardType: TextInputType.number,
              ),
              const Divider(height: 22),
              _SexRow(
                value: sex,
                onChanged: (value) => setState(() => sex = value),
              ),
              const Divider(height: 22),
              _InputRow(
                label: 'Birth date',
                value: widget.profile.birthDate,
                controller: birthDateController,
                suffix: '',
                keyboardType: TextInputType.datetime,
              ),
              const Divider(height: 22),
              _InputRow(
                label: 'Weight',
                value: widget.profile.weightKg > 0
                    ? '${widget.profile.weightKg.toStringAsFixed(1)} kg'
                    : 'Missing',
                controller: weightController,
                suffix: 'kg',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const Divider(height: 22),
              _InputRow(
                label: 'Height',
                value: widget.profile.heightCm > 0
                    ? '${widget.profile.heightCm.toStringAsFixed(0)} cm'
                    : 'Missing',
                controller: heightController,
                suffix: 'cm',
                keyboardType: TextInputType.number,
              ),
              const Divider(height: 22),
              _InputRow(
                label: 'Body fat',
                value: widget.profile.bodyFatPercent > 0
                    ? '${widget.profile.bodyFatPercent.toStringAsFixed(1)}%'
                    : 'Missing',
                controller: fatController,
                suffix: '%',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                'Analysis impact',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _analysisText(widget.profile),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _analysisText(PersonalProfile profile) {
    final hasProfile =
        profile.age > 0 || profile.weightKg > 0 || profile.bodyFatPercent > 0;
    if (!hasProfile) {
      return 'Add age, weight, height, and body composition to make sleep, recovery, strain, and temperature insights more personal.';
    }

    return 'Age, body mass, height, sex, and body-fat context are now available for conclusions around recovery, sleep need, cardio load, and baseline temperature.';
  }
}

class _AccountBadge extends StatelessWidget {
  const _AccountBadge({required this.account});

  final QuantivitaAccount account;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${account.isAppleLinked ? 'Apple-linked' : 'Local'} account\n${account.accountId}',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _IntegrationRow extends StatelessWidget {
  const _IntegrationRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.statusLabel,
    required this.isConnected,
    required this.isLoading,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String statusLabel;
  final bool isConnected;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: QuantivitaColors.activity),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              Text(statusLabel, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: isConnected
                ? Theme.of(context).colorScheme.error
                : null,
            foregroundColor: isConnected ? Colors.white : null,
          ),
          child: Text(
            isLoading
                ? isConnected
                      ? 'Disconnecting...'
                      : 'Connecting...'
                : isConnected
                ? 'Disconnect'
                : 'Connect',
          ),
        ),
      ],
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.label,
    required this.value,
    required this.controller,
    required this.suffix,
    required this.keyboardType,
  });

  final String label;
  final String value;
  final TextEditingController controller;
  final String suffix;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                const SizedBox(height: 5),
                Text(value, style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          SizedBox(
            width: 126,
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleMedium,
              decoration: InputDecoration(
                suffixText: suffix,
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: theme.colorScheme.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: theme.colorScheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SexRow extends StatelessWidget {
  const _SexRow({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = ['Not set', 'Female', 'Male', 'Other'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Biological sex', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(option),
                  selected: value == option,
                  showCheckmark: false,
                  selectedColor: QuantivitaColors.recovery,
                  backgroundColor: theme.colorScheme.surface,
                  labelStyle: theme.textTheme.labelMedium?.copyWith(
                    color: value == option
                        ? QuantivitaColors.onAccent
                        : theme.colorScheme.onSurface,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(color: theme.colorScheme.outline),
                  ),
                  onSelected: (_) => onChanged(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
