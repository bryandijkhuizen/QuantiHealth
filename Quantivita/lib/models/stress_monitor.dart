enum StressFilter { today, sleep, nonActivity }

extension StressFilterLabel on StressFilter {
  String get label {
    return switch (this) {
      StressFilter.today => 'Today',
      StressFilter.sleep => 'Sleep',
      StressFilter.nonActivity => 'Non-activity',
    };
  }
}

class StressMonitor {
  const StressMonitor({
    required this.score,
    required this.highest,
    required this.lowest,
    required this.average,
    required this.lowPercent,
    required this.mediumPercent,
    required this.highPercent,
    required this.duration,
    required this.samples,
  });

  final int score;
  final int highest;
  final int lowest;
  final int average;
  final int lowPercent;
  final int mediumPercent;
  final int highPercent;
  final String duration;
  final List<double> samples;
}
