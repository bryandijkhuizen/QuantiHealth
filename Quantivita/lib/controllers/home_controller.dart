import 'dart:async';

import 'package:flutter/material.dart';

import '../health/scoring/baseline_service.dart';
import '../health/scoring/body_battery_service.dart';
import '../health/scoring/recovery_scoring_service.dart';
import '../health/scoring/scoring_types.dart';
import '../health/scoring/sleep_need_service.dart';
import '../health/scoring/strain_scoring_service.dart';
import '../models/dashboard_snapshot.dart';
import '../models/dashboard_widget_id.dart';
import '../models/fitness_summary.dart';
import '../models/metric_model.dart';
import '../models/personal_profile.dart';
import '../models/sleep_summary.dart';
import '../models/stress_monitor.dart';
import '../services/account_service.dart';
import '../services/apple_auth_service.dart';
import '../services/dashboard_cache_service.dart';
import '../services/health_permission_service.dart';
import '../services/homeserver_sync_service.dart';
import '../services/profile_storage_service.dart';
import '../services/progressa_integration_service.dart';
import '../theme/quantivita_colors.dart';

enum AppStage { auth, permissions, dashboard }

class HomeController extends ChangeNotifier {
  HomeController({
    AppleAuthService? appleAuthService,
    AccountService? accountService,
    HealthPermissionService? healthPermissionService,
    DashboardCacheService? dashboardCacheService,
    HomeserverSyncService? homeserverSyncService,
    ProfileStorageService? profileStorageService,
    ProgressaIntegrationService? progressaIntegrationService,
  }) : _appleAuthService = appleAuthService ?? AppleAuthService(),
       _accountService = accountService ?? AccountService(),
       _dashboardCacheService =
           dashboardCacheService ?? DashboardCacheService(),
       _healthPermissionService =
           healthPermissionService ?? HealthPermissionService(),
       _homeserverSyncService =
           homeserverSyncService ?? HomeserverSyncService(),
       _profileStorageService =
           profileStorageService ?? ProfileStorageService(),
       _progressaIntegrationService =
           progressaIntegrationService ?? ProgressaIntegrationService() {
    _loadStoredProfile();
  }

  final AppleAuthService _appleAuthService;
  final AccountService _accountService;
  final DashboardCacheService _dashboardCacheService;
  final HealthPermissionService _healthPermissionService;
  final HomeserverSyncService _homeserverSyncService;
  final ProfileStorageService _profileStorageService;
  final ProgressaIntegrationService _progressaIntegrationService;

  int selectedIndex = 0;
  bool isSigningIn = false;
  bool isRequestingHealthPermission = false;
  bool isLoadingWorkoutHistory = false;
  bool isSyncingProgressaWorkouts = false;
  bool isAppleAccountConnected = false;
  QuantivitaAccount? account;
  bool hasHealthPermission = false;
  bool hasHealthData = false;
  String? authMessage;
  DashboardSnapshot? dashboardSnapshot;
  Map<String, double> healthSummary = const {};
  Map<String, String> healthSummaryText = const {};
  List<FitnessEventSummary> progressaWorkoutEvents = const [];
  int workoutLookbackDays = 7;
  DateTime selectedWorkoutDate = DateTime.now();
  PersonalProfile personalProfile = PersonalProfile.empty();
  StressFilter stressFilter = StressFilter.today;
  Set<DashboardWidgetId> enabledDashboardWidgets = {
    DashboardWidgetId.readiness,
    DashboardWidgetId.metrics,
    DashboardWidgetId.stress,
  };
  AppStage stage = AppStage.auth;

  void selectTab(int index) {
    if (selectedIndex == index) return;
    selectedIndex = index;
    notifyListeners();
  }

  void updatePersonalProfile({
    int? age,
    String? birthDate,
    String? biologicalSex,
    double? weightKg,
    double? heightCm,
    double? bodyFatPercent,
  }) {
    personalProfile = personalProfile.copyWith(
      age: age,
      birthDate: birthDate,
      biologicalSex: biologicalSex,
      weightKg: weightKg,
      heightCm: heightCm,
      bodyFatPercent: bodyFatPercent,
    );
    unawaited(_profileStorageService.save(personalProfile));
    unawaited(_syncHomeserverInBackground());
    notifyListeners();
  }

  Future<void> _loadStoredProfile() async {
    final storedProfile = await _profileStorageService.load();
    final cachedDashboard = await _dashboardCacheService.load();
    account = await _accountService.loadAccount();
    isAppleAccountConnected = account?.isAppleLinked == true;
    if (storedProfile != null) {
      personalProfile = storedProfile;
    }
    if (cachedDashboard != null) {
      healthSummary = cachedDashboard.healthSummary;
      healthSummaryText = cachedDashboard.healthSummaryText;
      personalProfile = _mergeHealthProfile(
        PersonalProfile.fromSummary(cachedDashboard.healthSummary),
      );
      _refreshDashboardSnapshot();
    }
    if (account != null) {
      stage = dashboardSnapshot != null
          ? AppStage.dashboard
          : AppStage.permissions;
      notifyListeners();
      unawaited(_loadCachedProgressaWorkouts());
      unawaited(_bootstrapHealthAfterStoredLogin());
      return;
    }
    notifyListeners();
  }

  Future<void> _bootstrapHealthAfterStoredLogin() async {
    await requestHealthPermissions(showMessage: false);
  }

  Future<void> refreshHealthData() async {
    await requestHealthPermissions(showMessage: false);
  }

  Future<void> continueOffline() async {
    if (isSigningIn) return;

    isSigningIn = true;
    authMessage = null;
    notifyListeners();

    account = await _accountService.ensureLocalAccount();
    isAppleAccountConnected = false;
    final cachedDashboard = await _dashboardCacheService.load();
    if (cachedDashboard != null) {
      healthSummary = cachedDashboard.healthSummary;
      healthSummaryText = cachedDashboard.healthSummaryText;
      personalProfile = _mergeHealthProfile(
        PersonalProfile.fromSummary(cachedDashboard.healthSummary),
      );
      _refreshDashboardSnapshot();
    }
    stage = AppStage.dashboard;
    authMessage = cachedDashboard == null
        ? 'Offline mode started. Connect Apple Health when it is available.'
        : 'Showing your last saved Quantivita dashboard.';
    isSigningIn = false;
    notifyListeners();

    unawaited(_loadCachedProgressaWorkouts());
    unawaited(_bootstrapHealthAfterStoredLogin());
  }

  void selectStressFilter(StressFilter filter) {
    if (stressFilter == filter) return;
    stressFilter = filter;
    notifyListeners();
  }

  void selectWorkoutDate(DateTime date) {
    selectedWorkoutDate = DateTime(date.year, date.month, date.day);
    notifyListeners();
  }

  void shiftWorkoutDate(int days) {
    selectWorkoutDate(selectedWorkoutDate.add(Duration(days: days)));
  }

  Future<void> updateWorkoutLookbackDays(int days) async {
    if (isLoadingWorkoutHistory || workoutLookbackDays == days) return;

    workoutLookbackDays = days;
    isLoadingWorkoutHistory = true;
    authMessage = null;
    notifyListeners();

    final result = await _healthPermissionService.loadWorkoutHistory(days);

    if (result.status == HealthPermissionStatus.connected) {
      healthSummary = _mergeWorkoutHistory(healthSummary, result.summary);
      healthSummaryText = _mergeWorkoutTextHistory(
        healthSummaryText,
        result.textSummary,
      );
      _refreshDashboardSnapshot();
      unawaited(
        _dashboardCacheService.save(
          healthSummary: healthSummary,
          healthSummaryText: healthSummaryText,
        ),
      );
      authMessage = result.message;
      unawaited(_syncHomeserverInBackground());
    } else {
      authMessage = result.message;
    }

    isLoadingWorkoutHistory = false;
    notifyListeners();
  }

  Future<void> syncProgressaWorkouts() async {
    if (isSyncingProgressaWorkouts) return;

    isSyncingProgressaWorkouts = true;
    authMessage = null;
    notifyListeners();

    final result = await _progressaIntegrationService.fetchWorkouts(
      from: DateTime.now().subtract(
        Duration(days: workoutLookbackDays < 365 ? 365 : workoutLookbackDays),
      ),
      to: DateTime.now(),
      limit: 100,
    );

    if (result.success) {
      progressaWorkoutEvents = result.workouts;
      _refreshDashboardSnapshot();
      authMessage = result.message;
      unawaited(_syncHomeserverInBackground());
    } else {
      authMessage = result.message;
    }

    isSyncingProgressaWorkouts = false;
    notifyListeners();
  }

  void toggleDashboardWidget(DashboardWidgetId widgetId) {
    final next = Set<DashboardWidgetId>.from(enabledDashboardWidgets);
    if (!next.add(widgetId)) {
      next.remove(widgetId);
    }

    if (next.isEmpty) {
      next.add(DashboardWidgetId.readiness);
    }

    enabledDashboardWidgets = next;
    notifyListeners();
  }

  void setDashboardWidgets(Set<DashboardWidgetId> widgetIds) {
    enabledDashboardWidgets = widgetIds.isEmpty
        ? {DashboardWidgetId.readiness}
        : Set<DashboardWidgetId>.from(widgetIds);
    notifyListeners();
  }

  FitnessSummary get fitnessSummary {
    final lastWorkoutStart = healthSummary['lastWorkoutStart'] ?? 0;
    final lastWorkoutDuration =
        healthSummary['lastWorkoutDurationMinutes'] ?? 0;
    final lastWorkoutEnergy = healthSummary['lastWorkoutEnergyKcal'] ?? 0;
    final workoutEvents = _workoutEvents();
    final strainResult = _strainResult(workoutEvents);
    final strainPercent = _strainPercent(strainResult);

    return FitnessSummary(
      strain: strainPercent.toDouble(),
      cardioLoad: strainResult.totalLoad.round().clamp(0, 999),
      cardioFocus: strainPercent >= 45 ? 'Aerobic' : 'Base',
      hrr: _heartRateReserveLabel(workoutEvents),
      loadSamples: const [0.18, 0.22, 0.26, 0.31, 0.28, 0.38, 0.42],
      focusSamples: const [0.12, 0.2, 0.18, 0.3, 0.36, 0.3, 0.44],
      events: workoutEvents.isNotEmpty
          ? workoutEvents
          : [
              FitnessEventSummary(
                id: 'latest',
                sourceUuid: '',
                title: 'Latest workout',
                subtitle: lastWorkoutStart > 0
                    ? _formatTimestamp(lastWorkoutStart)
                    : 'No workout timestamp in Apple Health',
                value: lastWorkoutDuration > 0
                    ? '${lastWorkoutDuration.round()} min'
                    : 'No data',
                startTime: lastWorkoutStart,
                durationMinutes: lastWorkoutDuration,
                energyKcal: lastWorkoutEnergy,
                totalEnergyKcal: lastWorkoutEnergy,
                distanceMeters: 0,
                elevationGainMeters: 0,
                averageHeartRate: 0,
                maxHeartRate: 0,
                temperatureC: 0,
                humidityPercent: 0,
                weatherCondition: '',
                airQualityIndex: 0,
                typeCode: 0,
                hasRoute: false,
              ),
              FitnessEventSummary(
                id: 'energy',
                sourceUuid: '',
                title: 'Energy',
                subtitle: 'Latest workout active energy',
                value: lastWorkoutEnergy > 0
                    ? '${lastWorkoutEnergy.round()} kcal'
                    : 'No data',
                startTime: lastWorkoutStart,
                durationMinutes: lastWorkoutDuration,
                energyKcal: lastWorkoutEnergy,
                totalEnergyKcal: lastWorkoutEnergy,
                distanceMeters: 0,
                elevationGainMeters: 0,
                averageHeartRate: 0,
                maxHeartRate: 0,
                temperatureC: 0,
                humidityPercent: 0,
                weatherCondition: '',
                airQualityIndex: 0,
                typeCode: 0,
                hasRoute: false,
              ),
            ],
    );
  }

  List<FitnessEventSummary> _workoutEvents() {
    final events = <FitnessEventSummary>[];

    for (var index = 1; index <= 50; index++) {
      final start = healthSummary['workout${index}Start'] ?? 0;
      if (start <= 0) continue;

      final duration = healthSummary['workout${index}DurationMinutes'] ?? 0;
      final energy = healthSummary['workout${index}EnergyKcal'] ?? 0;
      final totalEnergy =
          healthSummary['workout${index}TotalEnergyKcal'] ?? energy;
      final distance = healthSummary['workout${index}DistanceMeters'] ?? 0;
      final elevation =
          healthSummary['workout${index}ElevationGainMeters'] ?? 0;
      final avgHeartRate =
          healthSummary['workout${index}AverageHeartRate'] ?? 0;
      final maxHeartRate = healthSummary['workout${index}MaxHeartRate'] ?? 0;
      final temperature = healthSummary['workout${index}TemperatureC'] ?? 0;
      final humidity = healthSummary['workout${index}HumidityPercent'] ?? 0;
      final weatherCondition =
          healthSummaryText['workout${index}WeatherCondition'] ?? '';
      final airQuality = healthSummary['workout${index}AirQualityIndex'] ?? 0;
      final type = healthSummary['workout${index}Type'] ?? 0;
      final hasRoute = (healthSummary['workout${index}HasRoute'] ?? 0) > 0;
      final sourceUuid = healthSummaryText['workout${index}Uuid'] ?? '';

      events.add(
        FitnessEventSummary(
          id: 'healthkit-workout-$index-${start.round()}',
          sourceUuid: sourceUuid,
          title: _workoutTitle(type, index),
          subtitle: [
            _formatTimestamp(start),
            if (energy > 0) '${energy.round()} kcal',
            if (distance > 0) _formatDistance(distance),
            if (hasRoute) 'GPS',
          ].join(' • '),
          value: duration > 0 ? '${duration.round()} min' : 'No duration',
          startTime: start,
          durationMinutes: duration,
          energyKcal: energy,
          totalEnergyKcal: totalEnergy,
          distanceMeters: distance,
          elevationGainMeters: elevation,
          averageHeartRate: avgHeartRate,
          maxHeartRate: maxHeartRate,
          temperatureC: temperature,
          humidityPercent: humidity,
          weatherCondition: weatherCondition,
          airQualityIndex: airQuality,
          typeCode: type.round(),
          hasRoute: hasRoute,
        ),
      );
    }

    events.addAll(progressaWorkoutEvents);
    events.sort((a, b) => b.startTime.compareTo(a.startTime));
    return events;
  }

  StrainScoreResult _strainResult(List<FitnessEventSummary> events) {
    final today = DateTime.now();
    final todayEvents = events.where((event) {
      if (event.startTime <= 0) return false;
      final date = DateTime.fromMillisecondsSinceEpoch(
        (event.startTime * 1000).round(),
      );
      return date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
    }).toList();
    return StrainScoringService.calculate(
      StrainScoreInput(
        userP90DailyLoad: 120,
        workouts: [
          for (final event in todayEvents)
            StrainWorkoutInput(
              durationMinutes: event.effectiveDurationMinutes,
              activeEnergyKcal: event.effectiveEnergyKcal,
              averageHeartRate: event.averageHeartRate,
              typeCode: event.typeCode,
              restingHeartRate: healthSummary['restingHeartBpm'],
              maxHeartRate: healthSummary['maxHeartBpm'] ?? event.maxHeartRate,
            ),
        ],
      ),
    );
  }

  String _workoutTitle(double type, int index) {
    return switch (type.round()) {
      1 => 'Run',
      2 => 'Walk',
      3 => 'Cycle',
      4 => 'Swim',
      5 => 'Strength',
      6 => 'HIIT',
      7 => 'Yoga',
      8 => 'Hike',
      9 => 'Elliptical',
      10 => 'Rowing',
      11 => 'Rock Climbing',
      12 => 'Pilates',
      13 => 'Dance',
      14 => 'Stair Climbing',
      15 => 'Tennis',
      16 => 'Soccer',
      17 => 'Basketball',
      18 => 'Core Training',
      19 => 'Paddling',
      _ => 'Workout',
    };
  }

  String _formatTimestamp(double epochSeconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      (epochSeconds * 1000).round(),
    );
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month} $hour:$minute';
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  StressMonitor get stressMonitor {
    final base = switch (stressFilter) {
      StressFilter.today => const [
        0.08,
        0.22,
        0.23,
        0.06,
        0.1,
        0.34,
        0.26,
        0.12,
        0.08,
        0.14,
        0.06,
        0.04,
      ],
      StressFilter.sleep => const [
        0.04,
        0.08,
        0.06,
        0.16,
        0.1,
        0.08,
        0.05,
        0.07,
        0.03,
        0.04,
      ],
      StressFilter.nonActivity => const [
        0.12,
        0.2,
        0.18,
        0.29,
        0.16,
        0.24,
        0.4,
        0.22,
        0.18,
        0.26,
      ],
    };

    final values = base.map((value) => value * 100).toList();
    final highest = values.reduce((a, b) => a > b ? a : b).round();
    final lowest = values.reduce((a, b) => a < b ? a : b).round();
    final average = (values.reduce((a, b) => a + b) / values.length).round();

    return StressMonitor(
      score: average.clamp(0, 100),
      highest: highest,
      lowest: lowest,
      average: average,
      lowPercent: stressFilter == StressFilter.nonActivity ? 72 : 93,
      mediumPercent: stressFilter == StressFilter.nonActivity ? 23 : 7,
      highPercent: stressFilter == StressFilter.nonActivity ? 5 : 0,
      duration: stressFilter == StressFilter.today ? '7:06:00' : '6:36:00',
      samples: base,
    );
  }

  Future<void> signInWithApple() async {
    if (isSigningIn) return;

    isSigningIn = true;
    authMessage = null;
    notifyListeners();

    final result = await _appleAuthService.signIn();

    switch (result.status) {
      case AppleAuthStatus.signedIn:
        if (result.userIdentifier != null) {
          account = await _accountService.linkAppleUser(result.userIdentifier!);
        }
        isAppleAccountConnected = account?.isAppleLinked == true;
        stage = AppStage.permissions;
      case AppleAuthStatus.canceled:
        break;
      case AppleAuthStatus.unavailable:
        authMessage =
            result.message ??
            'Enable Sign in with Apple in Xcode before testing.';
      case AppleAuthStatus.failed:
        authMessage = result.message ?? 'Apple sign in could not be completed.';
    }

    isSigningIn = false;
    notifyListeners();
  }

  Future<void> requestHealthPermissions({bool showMessage = true}) async {
    if (isRequestingHealthPermission) return;

    isRequestingHealthPermission = true;
    authMessage = null;
    notifyListeners();

    final result = await _healthPermissionService.requestAuthorization();

    switch (result.status) {
      case HealthPermissionStatus.connected:
        hasHealthPermission = true;
        hasHealthData = true;
        healthSummary = result.summary;
        healthSummaryText = result.textSummary;
        workoutLookbackDays =
            (result.summary['workoutLookbackDays'] ?? workoutLookbackDays)
                .round();
        personalProfile = _mergeHealthProfile(
          PersonalProfile.fromSummary(result.summary),
        );
        _refreshDashboardSnapshot();
        unawaited(
          _dashboardCacheService.save(
            healthSummary: healthSummary,
            healthSummaryText: healthSummaryText,
          ),
        );
        stage = AppStage.dashboard;
        authMessage = showMessage ? result.message : null;
        unawaited(_syncHomeserverInBackground());
        unawaited(_syncProgressaIfConnected());
      case HealthPermissionStatus.noData:
        hasHealthPermission = true;
        hasHealthData = false;
        healthSummary = result.summary;
        healthSummaryText = result.textSummary;
        workoutLookbackDays =
            (result.summary['workoutLookbackDays'] ?? workoutLookbackDays)
                .round();
        personalProfile = _mergeHealthProfile(
          PersonalProfile.fromSummary(result.summary),
        );
        dashboardSnapshot = null;
        unawaited(
          _dashboardCacheService.save(
            healthSummary: healthSummary,
            healthSummaryText: healthSummaryText,
          ),
        );
        stage = AppStage.dashboard;
        authMessage = showMessage ? result.message : null;
        unawaited(_syncHomeserverInBackground());
        unawaited(_syncProgressaIfConnected());
      case HealthPermissionStatus.denied:
        hasHealthPermission = false;
        hasHealthData = false;
        authMessage = result.message;
      case HealthPermissionStatus.unavailable:
      case HealthPermissionStatus.failed:
        hasHealthPermission = false;
        hasHealthData = false;
        authMessage = result.message;
    }

    isRequestingHealthPermission = false;
    notifyListeners();
  }

  Future<void> _syncHomeserverInBackground() async {
    if (account == null || healthSummary.isEmpty) return;
    final result = await _homeserverSyncService.sync(
      profile: personalProfile,
      healthSummary: healthSummary,
      fitnessSummary: fitnessSummary,
    );
    if (!result.success) {
      authMessage = result.message;
      notifyListeners();
    }
  }

  Future<void> _syncProgressaIfConnected() async {
    if (isSyncingProgressaWorkouts) {
      return;
    }
    if (progressaWorkoutEvents.isEmpty) {
      await _loadCachedProgressaWorkouts();
    }
    final status = await _progressaIntegrationService.isConnected();
    if (status.connected == true) {
      await syncProgressaWorkouts();
    }
  }

  Future<void> _loadCachedProgressaWorkouts() async {
    final cached = await _progressaIntegrationService.loadCachedWorkouts();
    if (cached.isEmpty) return;
    progressaWorkoutEvents = cached;
    _refreshDashboardSnapshot();
    notifyListeners();
  }

  void _refreshDashboardSnapshot() {
    if (healthSummary.isNotEmpty) {
      dashboardSnapshot = _buildSnapshot(healthSummary);
    }
  }

  SleepSummary get sleepSummary => SleepSummary.fromSummary(healthSummary);

  Map<String, double> _mergeWorkoutHistory(
    Map<String, double> current,
    Map<String, double> workoutHistory,
  ) {
    final next = Map<String, double>.from(current)
      ..removeWhere(
        (key, _) =>
            key.startsWith('workout') ||
            key == 'lastWorkoutStart' ||
            key == 'lastWorkoutDurationMinutes' ||
            key == 'lastWorkoutEnergyKcal' ||
            key == 'lastWorkoutDistanceMeters',
      );
    next.addAll(workoutHistory);
    return next;
  }

  Map<String, String> _mergeWorkoutTextHistory(
    Map<String, String> current,
    Map<String, String> workoutHistory,
  ) {
    final next = Map<String, String>.from(current)
      ..removeWhere((key, _) => key.startsWith('workout'));
    next.addAll(workoutHistory);
    return next;
  }

  PersonalProfile _mergeHealthProfile(PersonalProfile healthProfile) {
    return personalProfile.copyWith(
      age: healthProfile.age > 0 ? healthProfile.age : personalProfile.age,
      birthDate: healthProfile.birthDate != 'Not set'
          ? healthProfile.birthDate
          : personalProfile.birthDate,
      biologicalSex: healthProfile.biologicalSex != 'Not set'
          ? healthProfile.biologicalSex
          : personalProfile.biologicalSex,
      weightKg: healthProfile.weightKg > 0
          ? healthProfile.weightKg
          : personalProfile.weightKg,
      heightCm: healthProfile.heightCm > 0
          ? healthProfile.heightCm
          : personalProfile.heightCm,
      bodyFatPercent: healthProfile.bodyFatPercent > 0
          ? healthProfile.bodyFatPercent
          : personalProfile.bodyFatPercent,
    );
  }

  DashboardSnapshot _buildSnapshot(Map<String, double> summary) {
    final steps = summary['steps'] ?? 0;
    final hrv = summary['hrvMs'] ?? 0;
    final restingHeartRate = summary['restingHeartBpm'] ?? 0;
    final sleepMinutes = summary['sleepMinutes'] ?? 0;
    final respiratoryRate = summary['respiratoryRate'] ?? 0;
    final oxygenSaturation = summary['oxygenSaturation'] ?? 0;
    final bodyTemperature = summary['bodyTemperatureC'] ?? 0;
    final wristTemperature = summary['wristTemperatureC'] ?? 0;
    final activeEnergyKcal = summary['activeEnergyKcal'] ?? 0;
    final basalEnergyKcal = _basalEnergyKcal(summary);
    final dietaryEnergyKcal = summary['dietaryEnergyKcal'] ?? 0;
    final dietaryWaterMl = summary['dietaryWaterMl'] ?? 0;
    final workoutMinutes = _todayWorkoutMinutes();
    final waterBaseTargetMl = _waterBaseTargetMl(summary);
    final waterActivityExtraMl = activeEnergyKcal * 0.35;
    final waterWorkoutExtraMl = workoutMinutes * 8;
    final waterTargetMl =
        (waterBaseTargetMl + waterActivityExtraMl + waterWorkoutExtraMl).clamp(
          1800.0,
          4500.0,
        );
    final totalBurnedEnergyKcal = activeEnergyKcal + basalEnergyKcal;
    final netEnergyKcal = dietaryEnergyKcal - totalBurnedEnergyKcal;
    final sleepScore = sleepSummary.qualityScore;
    final strainResult = _strainResult(_workoutEvents());
    final strainPercent = _strainPercent(strainResult);
    final baselines = BaselineService.fromToday(
      hrvMs: hrv,
      restingHeartRate: restingHeartRate,
      sleepMinutes: sleepMinutes,
      sleepEfficiency: sleepSummary.efficiency,
      strainLoad: strainResult.totalLoad,
      stressScore: stressMonitor.average.toDouble(),
      respiratoryRate: respiratoryRate,
      temperatureDeviation: wristTemperature > 0 && bodyTemperature > 0
          ? wristTemperature - bodyTemperature
          : 0,
    );
    final recoveryResult = RecoveryScoringService.calculate(
      input: RecoveryScoreInput(
        sleepDurationMinutes: sleepMinutes,
        sleepScore: sleepScore,
        sleepAvailable: sleepMinutes > 0,
        hrvRmssd: hrv,
        restingHeartRate: restingHeartRate,
        strainLoadToday: strainResult.totalLoad,
        stressScore: stressMonitor.average.toDouble(),
        respiratoryRate: respiratoryRate > 0 ? respiratoryRate : null,
        temperatureDeviation: wristTemperature > 0 && bodyTemperature > 0
            ? wristTemperature - bodyTemperature
            : null,
      ),
      baselines: baselines,
    );
    final sleepNeed = SleepNeedService.calculate(
      actualSleepMinutes: sleepMinutes,
      strainPercent: strainPercent.toDouble(),
    );
    final bodyBattery = BodyBatteryService.calculate(
      recoveryScore: recoveryResult.score,
      sleepScore: sleepScore,
      strainPercent: strainPercent.toDouble(),
      stressScore: stressMonitor.average,
      activeEnergyKcal: activeEnergyKcal,
      steps: steps,
    );

    return DashboardSnapshot(
      bodyBatteryScore: bodyBattery.score,
      bodyBatteryTitle: bodyBattery.title,
      bodyBatterySummary: bodyBattery.summary,
      bodyBatteryFactors: bodyBattery.factors,
      recoveryScore: recoveryResult.score,
      recoveryLabel: 'Recovery',
      recoveryTitle: recoveryResult.label,
      recoverySummary: recoveryResult.summary,
      recoveryConfidence: recoveryResult.confidence,
      sleepDuration: _formatSleep(sleepMinutes),
      sleepNeed: _formatSleep(sleepNeed.needMinutes),
      sleepPerformanceScore: sleepNeed.performanceScore,
      sleepNeedSummary: sleepNeed.summary,
      hrvDelta: hrv > 0 ? '${hrv.round()} ms' : 'No HRV',
      restingHeartRate: restingHeartRate > 0
          ? '${restingHeartRate.round()} bpm'
          : 'No RHR',
      respiratoryRate: respiratoryRate > 0
          ? '${respiratoryRate.toStringAsFixed(1)} rpm'
          : 'No RR',
      oxygenSaturation: oxygenSaturation > 0
          ? '${oxygenSaturation.toStringAsFixed(0)}%'
          : 'No SpO2',
      baseTemperature: bodyTemperature > 0
          ? '${bodyTemperature.toStringAsFixed(1)} °C'
          : 'No temp',
      wristTemperature: wristTemperature > 0
          ? '${wristTemperature.toStringAsFixed(1)} °C'
          : 'No wrist temp',
      dietaryEnergyKcal: dietaryEnergyKcal,
      dietaryWaterMl: dietaryWaterMl,
      waterTargetMl: waterTargetMl,
      waterBaseTargetMl: waterBaseTargetMl,
      waterActivityExtraMl: waterActivityExtraMl,
      waterWorkoutExtraMl: waterWorkoutExtraMl,
      activeEnergyKcal: activeEnergyKcal,
      basalEnergyKcal: basalEnergyKcal,
      totalBurnedEnergyKcal: totalBurnedEnergyKcal,
      netEnergyKcal: netEnergyKcal,
      dietaryCarbohydratesG: summary['dietaryCarbohydratesG'] ?? 0,
      dietaryProteinG: summary['dietaryProteinG'] ?? 0,
      dietaryFatG: summary['dietaryFatG'] ?? 0,
      metrics: [
        MetricModel(
          icon: Icons.bolt_rounded,
          title: 'Strain',
          value: strainPercent.toString(),
          unit: '%',
          color: QuantivitaColors.strain,
          caption: '${strainResult.label} daily load',
          samples: const [0.1, 0.14, 0.18, 0.24, 0.28, 0.32, 0.36],
        ),
        MetricModel(
          icon: Icons.nights_stay_rounded,
          title: 'Sleep',
          value: _formatSleep(sleepMinutes),
          unit: '',
          color: QuantivitaColors.sleep,
          caption:
              '${sleepNeed.performanceScore}% performance • need ${_formatSleep(sleepNeed.needMinutes)}',
          samples: const [0.2, 0.2, 0.24, 0.24, 0.28, 0.3, 0.34],
        ),
        MetricModel(
          icon: Icons.favorite_rounded,
          title: 'Heart',
          value: restingHeartRate > 0
              ? restingHeartRate.round().toString()
              : '-',
          unit: restingHeartRate > 0 ? 'bpm' : '',
          color: QuantivitaColors.stress,
          caption: 'Resting heart rate',
          samples: const [0.34, 0.32, 0.3, 0.31, 0.29, 0.28, 0.27],
        ),
        MetricModel(
          icon: Icons.directions_walk_rounded,
          title: 'Activity',
          value: steps > 0 ? _formatSteps(steps) : '-',
          unit: '',
          color: QuantivitaColors.activity,
          caption: 'Steps today',
          samples: const [0.08, 0.12, 0.18, 0.2, 0.26, 0.31, 0.35],
        ),
      ],
      baselineTrend: 'Collecting',
      weekValues: const [0.16, 0.18, 0.22, 0.2, 0.24, 0.26, 0.3],
      weekInsight:
          'Quantivita needs a few days of local history before it can compare your baseline.',
    );
  }

  String _formatSleep(double minutes) {
    if (minutes <= 0) return '-';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes.round() % 60;
    return '${hours}h ${remainingMinutes}m';
  }

  String _formatSteps(double steps) {
    if (steps >= 1000) {
      return '${(steps / 1000).toStringAsFixed(1)}k';
    }

    return steps.round().toString();
  }

  int _strainPercent(StrainScoreResult result) {
    return (result.score / 21 * 100).round().clamp(0, 100);
  }

  double _basalEnergyKcal(Map<String, double> summary) {
    final basal = summary['basalEnergyKcal'] ?? 0;
    if (basal > 0) return basal;

    final weightKg = summary['bodyMassKg'] ?? personalProfile.weightKg;
    if (weightKg > 0) return weightKg * 22;

    return 1650;
  }

  double _waterBaseTargetMl(Map<String, double> summary) {
    final weightKg = summary['bodyMassKg'] ?? personalProfile.weightKg;
    return (weightKg > 0 ? weightKg : 75) * 35;
  }

  double _todayWorkoutMinutes() {
    final today = DateTime.now();
    return _workoutEvents()
        .where((event) {
          if (event.startTime <= 0) return false;
          final date = DateTime.fromMillisecondsSinceEpoch(
            (event.startTime * 1000).round(),
          );
          return date.year == today.year &&
              date.month == today.month &&
              date.day == today.day;
        })
        .fold<double>(
          0,
          (total, event) => total + event.effectiveDurationMinutes,
        );
  }

  String _heartRateReserveLabel(List<FitnessEventSummary> events) {
    final restingHeartRate = healthSummary['restingHeartBpm'] ?? 0;
    if (restingHeartRate <= 0) return 'No RHR';

    final maxFromWorkouts = events.fold<double>(
      0,
      (max, event) => event.maxHeartRate > max ? event.maxHeartRate : max,
    );
    final maxHeartRate = (healthSummary['maxHeartBpm'] ?? 0) > 0
        ? healthSummary['maxHeartBpm']!
        : maxFromWorkouts;
    if (maxHeartRate <= restingHeartRate) return 'No max HR';

    return '${(maxHeartRate - restingHeartRate).round()} bpm';
  }
}
