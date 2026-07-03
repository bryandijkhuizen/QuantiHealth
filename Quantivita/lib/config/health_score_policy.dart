class ScoreBand {
  const ScoreBand({
    required this.min,
    required this.label,
    required this.title,
    required this.summary,
  });

  final int min;
  final String label;
  final String title;
  final String summary;
}

abstract final class HealthScorePolicy {
  static const recoveryBands = [
    ScoreBand(
      min: 80,
      label: 'Ready',
      title: 'You look ready for meaningful work.',
      summary:
          'Recovery supports a normal training day. Watch HRV and resting heart rate before adding intensity.',
    ),
    ScoreBand(
      min: 65,
      label: 'Solid',
      title: 'Solid baseline, watch intensity.',
      summary:
          'Your signals are stable enough for steady movement and planned work.',
    ),
    ScoreBand(
      min: 45,
      label: 'Mixed',
      title: 'Mixed recovery signals today.',
      summary:
          'Keep the day flexible and let sleep, HRV, and stress decide the ceiling.',
    ),
    ScoreBand(
      min: 0,
      label: 'Low',
      title: 'Recovery is asking for a lighter day.',
      summary:
          'Lower intensity is sensible until sleep, HRV, or resting heart rate improves.',
    ),
  ];

  static const strainBands = [
    ScoreBand(
      min: 95,
      label: 'Very high',
      title: 'Very high daily strain',
      summary:
          'This is an exceptional daily load. Bias strongly toward recovery next.',
    ),
    ScoreBand(
      min: 80,
      label: 'High',
      title: 'High daily strain',
      summary: 'Protect the rest of the day and avoid stacking intensity.',
    ),
    ScoreBand(
      min: 55,
      label: 'Moderate',
      title: 'Moderate daily strain',
      summary: 'A productive training load if recovery signals are stable.',
    ),
    ScoreBand(
      min: 24,
      label: 'Light',
      title: 'Light daily strain',
      summary: 'Light load, suitable for an easier day.',
    ),
    ScoreBand(
      min: 0,
      label: 'Restorative',
      title: 'Restorative strain',
      summary: 'Very low load, mostly recovery or normal movement.',
    ),
  ];

  static const bodyBatteryBands = [
    ScoreBand(
      min: 75,
      label: 'High',
      title: 'Strong energy reserve',
      summary: 'Recovery and sleep are supporting the day so far.',
    ),
    ScoreBand(
      min: 50,
      label: 'Steady',
      title: 'Steady energy reserve',
      summary: 'You have usable capacity, but strain and stress still matter.',
    ),
    ScoreBand(
      min: 30,
      label: 'Low',
      title: 'Low energy reserve',
      summary: 'Keep intensity modest and protect recovery windows.',
    ),
    ScoreBand(
      min: 0,
      label: 'Depleted',
      title: 'Low energy reserve',
      summary: 'The day is asking for rest, food, sleep, or a gentler load.',
    ),
  ];

  static const sleepQualityBands = [
    ScoreBand(
      min: 85,
      label: 'Excellent',
      title: 'Excellent sleep quality',
      summary: 'Sleep efficiency and stage balance look strong.',
    ),
    ScoreBand(
      min: 70,
      label: 'Solid',
      title: 'Solid sleep quality',
      summary: 'Enough signal for a normal day, with room to optimize.',
    ),
    ScoreBand(
      min: 55,
      label: 'Light',
      title: 'Light sleep quality',
      summary: 'Treat sleep as a limiting factor for intensity.',
    ),
    ScoreBand(
      min: 0,
      label: 'Needs data',
      title: 'Sleep quality needs more data',
      summary: 'Sync sleep stages and in-bed time for a fuller score.',
    ),
  ];

  static const sleepTargetMinutes = 480.0;
  static const solidSleepMinutes = 390.0;
  static const greatSleepMinutes = 450.0;
  static const lowSleepMinutes = 330.0;
  static ScoreBand bandFor(int score, List<ScoreBand> bands) {
    return bands.firstWhere((band) => score >= band.min);
  }

  static int sleepDurationScore(double totalMinutes) {
    return (totalMinutes / sleepTargetMinutes * 100).round().clamp(0, 100);
  }
}
