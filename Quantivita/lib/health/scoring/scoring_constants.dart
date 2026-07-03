abstract final class ScoringConstants {
  static const recoveryWeights = {
    'hrv': 0.35,
    'rhr': 0.25,
    'sleep': 0.20,
    'strainBalance': 0.10,
    'respiratory': 0.05,
    'temperature': 0.05,
  };

  static const sleepWeights = {
    'duration': 0.30,
    'efficiency': 0.20,
    'restfulness': 0.15,
    'deep': 0.10,
    'rem': 0.10,
    'latency': 0.075,
    'timing': 0.075,
  };

  static const adultSleepTargetMinutes = 480.0;
  static const fallbackP90DailyLoad = 60.0;
  static const fallbackRestingHeartRate = 60.0;
  static const fallbackMaxHeartRate = 190.0;
}
