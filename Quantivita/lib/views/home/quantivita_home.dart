import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/home_controller.dart';
import '../../services/account_service.dart';
import '../../models/dashboard_snapshot.dart';
import '../../models/dashboard_widget_id.dart';
import '../../models/fitness_summary.dart';
import '../../models/metric_model.dart';
import '../../models/personal_profile.dart';
import '../../models/sleep_summary.dart';
import '../../models/stress_monitor.dart';
import '../auth/auth_screen.dart';
import '../details/sleep_detail_page.dart';
import '../details/metric_detail_page.dart';
import '../details/workout_detail_page.dart';
import '../permissions/permissions_screen.dart';
import 'widgets/biomarkers_tab.dart';
import 'widgets/fitness_tab.dart';
import 'widgets/header.dart';
import 'widgets/health_data_placeholder.dart';
import 'widgets/personalization_tab.dart';
import 'widgets/quantivita_nav_bar.dart';
import 'widgets/today_tab.dart';

class QuantivitaHome extends StatefulWidget {
  const QuantivitaHome({super.key});

  @override
  State<QuantivitaHome> createState() => _QuantivitaHomeState();
}

class _QuantivitaHomeState extends State<QuantivitaHome> {
  late final HomeController controller;

  @override
  void initState() {
    super.initState();
    controller = HomeController()..addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    controller
      ..removeListener(_handleControllerChange)
      ..dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    final message = controller.authMessage;
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return Scaffold(
      body: switch (controller.stage) {
        AppStage.auth => AuthScreen(
          isLoading: controller.isSigningIn,
          onAppleSignIn: controller.signInWithApple,
          onContinueOffline: controller.continueOffline,
        ),
        AppStage.permissions => PermissionsScreen(
          isLoading: controller.isRequestingHealthPermission,
          onAllowHealth: controller.requestHealthPermissions,
        ),
        AppStage.dashboard => _LiquidGlassBackdrop(
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: controller.refreshHealthData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: Header()),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
                    sliver: SliverList.list(
                      children: [
                        if (controller.hasHealthData &&
                            controller.dashboardSnapshot != null) ...[
                          _DashboardTabContent(
                            selectedIndex: controller.selectedIndex,
                            snapshot: controller.dashboardSnapshot!,
                            enabledWidgets: controller.enabledDashboardWidgets,
                            fitnessSummary: controller.fitnessSummary,
                            personalProfile: controller.personalProfile,
                            sleepSummary: controller.sleepSummary,
                            stressMonitor: controller.stressMonitor,
                            stressFilter: controller.stressFilter,
                            onMetricTap: (metric) {
                              final page = metric.title == 'Sleep'
                                  ? SleepDetailPage(
                                      summary: controller.sleepSummary,
                                    )
                                  : MetricDetailPage(metric: metric);
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(builder: (_) => page),
                              );
                            },
                            onDashboardWidgetsChanged:
                                controller.setDashboardWidgets,
                            onStressFilterChanged:
                                controller.selectStressFilter,
                            onWorkoutTap: (event) {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      WorkoutDetailPage(event: event),
                                ),
                              );
                            },
                            selectedWorkoutDate: controller.selectedWorkoutDate,
                            onWorkoutDateChanged: controller.selectWorkoutDate,
                            onWorkoutDateShifted: controller.shiftWorkoutDate,
                            onPersonalProfileChanged:
                                controller.updatePersonalProfile,
                            healthSummary: controller.healthSummary,
                            account: controller.account,
                            workoutLookbackDays: controller.workoutLookbackDays,
                            isLoadingWorkoutHistory:
                                controller.isLoadingWorkoutHistory,
                            isSyncingProgressaWorkouts:
                                controller.isSyncingProgressaWorkouts,
                            onWorkoutLookbackChanged:
                                controller.updateWorkoutLookbackDays,
                            onSyncProgressaWorkouts:
                                controller.syncProgressaWorkouts,
                          ),
                        ] else ...[
                          if (controller.selectedIndex == 3)
                            PersonalizationTab(
                              profile: controller.personalProfile,
                              healthSummary: controller.healthSummary,
                              fitnessSummary: controller.fitnessSummary,
                              account: controller.account,
                              onChanged: controller.updatePersonalProfile,
                            )
                          else
                            const HealthDataPlaceholder(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      },
      bottomNavigationBar: controller.stage == AppStage.dashboard
          ? QuantivitaNavBar(
              selectedIndex: controller.selectedIndex,
              onSelected: controller.selectTab,
            )
          : null,
    );
  }
}

class _LiquidGlassBackdrop extends StatelessWidget {
  const _LiquidGlassBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF071017), Color(0xFF101923), Color(0xFF080B10)]
              : const [Color(0xFFEAF6F7), Color(0xFFF8FAFB), Color(0xFFFFF2F0)],
        ),
      ),
      child: child,
    );
  }
}

class _DashboardTabContent extends StatelessWidget {
  const _DashboardTabContent({
    required this.selectedIndex,
    required this.snapshot,
    required this.enabledWidgets,
    required this.fitnessSummary,
    required this.personalProfile,
    required this.sleepSummary,
    required this.stressMonitor,
    required this.stressFilter,
    required this.onMetricTap,
    required this.onDashboardWidgetsChanged,
    required this.onStressFilterChanged,
    required this.onWorkoutTap,
    required this.selectedWorkoutDate,
    required this.onWorkoutDateChanged,
    required this.onWorkoutDateShifted,
    required this.onPersonalProfileChanged,
    required this.healthSummary,
    required this.account,
    required this.workoutLookbackDays,
    required this.isLoadingWorkoutHistory,
    required this.isSyncingProgressaWorkouts,
    required this.onWorkoutLookbackChanged,
    required this.onSyncProgressaWorkouts,
  });

  final int selectedIndex;
  final DashboardSnapshot snapshot;
  final Set<DashboardWidgetId> enabledWidgets;
  final FitnessSummary fitnessSummary;
  final PersonalProfile personalProfile;
  final SleepSummary sleepSummary;
  final StressMonitor stressMonitor;
  final Map<String, double> healthSummary;
  final QuantivitaAccount? account;
  final StressFilter stressFilter;
  final ValueChanged<MetricModel> onMetricTap;
  final ValueChanged<Set<DashboardWidgetId>> onDashboardWidgetsChanged;
  final ValueChanged<StressFilter> onStressFilterChanged;
  final ValueChanged<FitnessEventSummary> onWorkoutTap;
  final DateTime selectedWorkoutDate;
  final ValueChanged<DateTime> onWorkoutDateChanged;
  final ValueChanged<int> onWorkoutDateShifted;
  final int workoutLookbackDays;
  final bool isLoadingWorkoutHistory;
  final bool isSyncingProgressaWorkouts;
  final ValueChanged<int> onWorkoutLookbackChanged;
  final VoidCallback onSyncProgressaWorkouts;
  final void Function({
    int? age,
    String? birthDate,
    String? biologicalSex,
    double? weightKg,
    double? heightCm,
    double? bodyFatPercent,
  })
  onPersonalProfileChanged;

  @override
  Widget build(BuildContext context) {
    return switch (selectedIndex) {
      0 => TodayTab(
        snapshot: snapshot,
        enabledWidgets: enabledWidgets,
        fitnessSummary: fitnessSummary,
        stressMonitor: stressMonitor,
        stressFilter: stressFilter,
        onMetricTap: onMetricTap,
        onDashboardWidgetsChanged: onDashboardWidgetsChanged,
        onStressFilterChanged: onStressFilterChanged,
        onWorkoutTap: onWorkoutTap,
        selectedWorkoutDate: selectedWorkoutDate,
        onWorkoutDateChanged: onWorkoutDateChanged,
        onWorkoutDateShifted: onWorkoutDateShifted,
      ),
      1 => BiomarkersTab(
        snapshot: snapshot,
        stressMonitor: stressMonitor,
        stressFilter: stressFilter,
        onStressFilterChanged: onStressFilterChanged,
        onMetricTap: onMetricTap,
      ),
      2 => FitnessTab(
        summary: fitnessSummary,
        selectedDate: selectedWorkoutDate,
        lookbackDays: workoutLookbackDays,
        isLoadingHistory: isLoadingWorkoutHistory,
        isSyncingProgressaWorkouts: isSyncingProgressaWorkouts,
        onLookbackChanged: onWorkoutLookbackChanged,
        onSyncProgressaWorkouts: onSyncProgressaWorkouts,
      ),
      3 => PersonalizationTab(
        profile: personalProfile,
        healthSummary: healthSummary,
        fitnessSummary: fitnessSummary,
        account: account,
        onChanged: onPersonalProfileChanged,
      ),
      _ => TodayTab(
        snapshot: snapshot,
        enabledWidgets: enabledWidgets,
        fitnessSummary: fitnessSummary,
        stressMonitor: stressMonitor,
        stressFilter: stressFilter,
        onMetricTap: onMetricTap,
        onDashboardWidgetsChanged: onDashboardWidgetsChanged,
        onStressFilterChanged: onStressFilterChanged,
        onWorkoutTap: onWorkoutTap,
        selectedWorkoutDate: selectedWorkoutDate,
        onWorkoutDateChanged: onWorkoutDateChanged,
        onWorkoutDateShifted: onWorkoutDateShifted,
      ),
    };
  }
}
