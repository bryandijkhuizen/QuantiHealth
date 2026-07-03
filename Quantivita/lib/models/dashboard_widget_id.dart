enum DashboardWidgetId { readiness, metrics, stress }

extension DashboardWidgetLabel on DashboardWidgetId {
  String get label {
    return switch (this) {
      DashboardWidgetId.readiness => 'Readiness',
      DashboardWidgetId.metrics => 'Metrics',
      DashboardWidgetId.stress => 'Stress',
    };
  }
}
