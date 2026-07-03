import Foundation

enum CalibrationStatus: String, Equatable { case insufficientData, calibrating, ready }

struct MetricBaseline: Equatable {
    let median: Double
    let mad: Double
    let sampleCount: Int
}

struct HealthBaselines: Equatable {
    var hrvLog: MetricBaseline?
    var hrvMs: MetricBaseline?
    var restingHeartRate: MetricBaseline?
    var sleepDurationMinutes: MetricBaseline?
    var sleepEfficiency: MetricBaseline?
    var strainLoad: MetricBaseline?
    var stress: MetricBaseline?
    var respiratoryRate: MetricBaseline?
    var temperatureDeviation: MetricBaseline?

    var primarySampleCount: Int {
        [hrvLog?.sampleCount ?? 0, restingHeartRate?.sampleCount ?? 0, sleepDurationMinutes?.sampleCount ?? 0].max() ?? 0
    }
}

struct SleepScoreResult: Equatable {
    let score: Int
    let contributors: [String: Double]
    let penalties: [String]
    let confidence: Double
}

struct StrainScoreResult: Equatable {
    let score: Double
    let cardioLoad: Double
    let muscularLoad: Double
    let totalLoad: Double
    let zones: [String: Double]
    let label: String
    var percent: Double { (score / 21 * 100).rounded().clamped(to: 0...100) }
}

struct SleepNeedResult: Equatable {
    let needMinutes: Double
    let performanceScore: Int
    let strainNeedMinutes: Double
    let debtMinutes: Double
    let summary: String
}

struct BodyBatteryFactor: Equatable {
    let label: String
    let points: Double
    let detail: String
}

struct BodyBatteryResult: Equatable {
    let score: Int
    let title: String
    let summary: String
    let factors: [BodyBatteryFactor]
}

struct DailyScores: Equatable {
    let sleep: SleepScoreResult
    let strain: StrainScoreResult
    let recovery: RecoveryResult
    let sleepNeed: SleepNeedResult
    let bodyBattery: BodyBatteryResult
    let stressScore: Int
}

enum ScoringMath {
    static func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double { max(minimum, min(maximum, value)) }
    static func score(_ value: Double) -> Int { Int(value.rounded()).clamped(to: 0...100) }
    static func oneDecimal(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let index = Double(sorted.count - 1) * p
        let lower = Int(floor(index)), upper = Int(ceil(index))
        guard lower != upper else { return sorted[lower] }
        let weight = index - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    static func baseline(_ values: [Double]) -> MetricBaseline {
        let clean = values.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !clean.isEmpty else { return MetricBaseline(median: 0, mad: 0, sampleCount: 0) }
        let median = percentile(clean, 0.5)
        let deviations = clean.map { abs($0 - median) }.sorted()
        return MetricBaseline(median: median, mad: percentile(deviations, 0.5), sampleCount: clean.count)
    }

    static func robustZ(_ value: Double, _ baseline: MetricBaseline?) -> Double {
        guard let baseline, baseline.mad >= 0.0001 else { return 0 }
        return (value - baseline.median) / (1.4826 * baseline.mad)
    }

    static func sigmoid(_ z: Double) -> Int { score(100 / (1 + exp(-1.15 * z))) }
    static func calibration(_ samples: Int) -> CalibrationStatus { samples < 14 ? .insufficientData : samples < 42 ? .calibrating : .ready }
    static func confidence(_ status: CalibrationStatus, available: Int, expected: Int) -> Double {
        let calibration = status == .ready ? 1.0 : status == .calibrating ? 0.65 : 0.35
        let signals = expected <= 0 ? 1 : clamp(Double(available) / Double(expected), 0, 1)
        return oneDecimal(calibration * signals)
    }
}

enum BaselineScorer {
    static func fromToday(
        hrv: Double, restingHeartRate: Double, sleepMinutes: Double, sleepEfficiency: Double,
        strainLoad: Double, stress: Double, respiratoryRate: Double, temperatureDeviation: Double
    ) -> HealthBaselines {
        let hrvValues = seed(hrv, spread: 0.18)
        return HealthBaselines(
            hrvLog: ScoringMath.baseline(hrvValues.filter { $0 > 0 }.map(log)),
            hrvMs: ScoringMath.baseline(hrvValues),
            restingHeartRate: ScoringMath.baseline(seed(restingHeartRate, spread: 0.08)),
            sleepDurationMinutes: ScoringMath.baseline(seed(sleepMinutes, spread: 0.10)),
            sleepEfficiency: ScoringMath.baseline(seed(sleepEfficiency, spread: 0.04)),
            strainLoad: ScoringMath.baseline(seed(strainLoad, spread: 0.22)),
            stress: ScoringMath.baseline(seed(stress, spread: 0.20)),
            respiratoryRate: ScoringMath.baseline(seed(respiratoryRate, spread: 0.04)),
            temperatureDeviation: ScoringMath.baseline(seed(abs(temperatureDeviation) + 0.05, spread: 0.20))
        )
    }

    static func seed(_ value: Double, spread: Double, count: Int = 28) -> [Double] {
        guard value > 0 else { return [] }
        return (0..<count).map { max(value * (1 + sin(Double($0) * 1.7) * spread), 0.0001) }
    }
}

enum SleepScorer {
    static func calculate(
        duration: Double, efficiency: Double?, awake: Double?, rem: Double?, deep: Double?,
        latency: Double? = nil, midpointDifference: Double? = nil, baselineDuration: Double? = nil
    ) -> SleepScoreResult {
        let contributors = [
            "duration": durationScore(duration, baseline: baselineDuration),
            "efficiency": efficiencyScore(efficiency), "restfulness": restfulnessScore(awake),
            "deep": stageScore(deep, total: duration, minimum: 60, maximum: 110),
            "rem": stageScore(rem, total: duration, minimum: 75, maximum: 120),
            "latency": latencyScore(latency), "timing": timingScore(midpointDifference),
        ]
        let weights = ["duration": 0.30, "efficiency": 0.20, "restfulness": 0.15, "deep": 0.10, "rem": 0.10, "latency": 0.075, "timing": 0.075]
        var weighted = weights.reduce(0) { $0 + (contributors[$1.key] ?? 0) * $1.value }
        var penalties: [String] = []
        if duration > 0 && duration < 300 { weighted = min(weighted, 45); penalties.append("sleep_under_5h_cap") }
        else if duration > 0 && duration < 360 { weighted = min(weighted, 65); penalties.append("sleep_under_6h_cap") }
        else if duration > 600 { weighted = min(weighted, 85); penalties.append("sleep_over_10h_cap") }
        let available = [duration > 0, (efficiency ?? 0) > 0, awake != nil, (rem ?? 0) > 0, (deep ?? 0) > 0, latency != nil, midpointDifference != nil].filter { $0 }.count
        return SleepScoreResult(score: ScoringMath.score(weighted), contributors: contributors, penalties: penalties, confidence: ScoringMath.oneDecimal(ScoringMath.clamp(Double(available) / 7, 0.35, 1)))
    }

    static func durationScore(_ minutes: Double, baseline: Double?) -> Double {
        guard minutes > 0 else { return 0 }
        let target = ScoringMath.clamp((baseline ?? 0) > 0 ? baseline! : 480, 420, 540)
        return ScoringMath.clamp(100 - abs(minutes - target) * 0.35, 0, 100)
    }
    static func efficiencyScore(_ value: Double?) -> Double {
        guard let value, value > 0 else { return 70 }
        if value >= 0.90 { return 100 }; if value >= 0.85 { return 85 + (value - 0.85) * 300 }
        if value >= 0.75 { return 50 + (value - 0.75) * 350 }; return ScoringMath.clamp(value * 65, 0, 50)
    }
    static func restfulnessScore(_ awake: Double?) -> Double { awake.map { ScoringMath.clamp(100 - $0 * 0.8, 0, 100) } ?? 75 }
    static func stageScore(_ minutes: Double?, total: Double, minimum: Double, maximum: Double) -> Double {
        guard let minutes, minutes > 0, total > 0 else { return 70 }
        if minutes >= minimum && minutes <= maximum { return 100 }
        return ScoringMath.clamp(100 - abs(minutes - (minutes < minimum ? minimum : maximum)) * 0.55, 45, 100)
    }
    static func latencyScore(_ minutes: Double?) -> Double {
        guard let minutes else { return 80 }; if minutes <= 20 { return 100 }
        if minutes <= 45 { return ScoringMath.clamp(100 - (minutes - 20) * 1.4, 65, 100) }
        return ScoringMath.clamp(65 - (minutes - 45) * 1.2, 0, 65)
    }
    static func timingScore(_ difference: Double?) -> Double { difference.map { ScoringMath.clamp(100 - abs($0) * 0.5, 0, 100) } ?? 80 }
}

enum StrainScorer {
    static func calculate(workouts: [Workout], restingHeartRate: Double, maxHeartRate: Double = 0, userP90Load: Double? = nil) -> StrainScoreResult {
        var zones = ["z1": 0.0, "z2": 0.0, "z3": 0.0, "z4": 0.0, "z5": 0.0]
        var cardio = 0.0, muscular = 0.0
        for workout in workouts {
            let duration = ScoringMath.clamp(workout.effectiveDurationMinutes, 0, 600)
            let resting = restingHeartRate > 0 ? restingHeartRate : 60
            let maximum = workout.maxHeartRate > 0 ? workout.maxHeartRate : maxHeartRate > 0 ? maxHeartRate : 190
            let reserve = max(maximum - resting, 1)
            let reservePercent = workout.averageHeartRate > 0 ? (workout.averageHeartRate - resting) / reserve : estimatedReserve(energy: workout.effectiveEnergyKcal, duration: duration)
            let zone = zone(reservePercent)
            zones[zone.name, default: 0] += duration; cardio += duration * zone.weight
            muscular += muscularLoad(workout, duration: duration)
        }
        let total = cardio + muscular * 0.35
        let k = max((userP90Load ?? 60) * 1.45, 110)
        let score = ScoringMath.oneDecimal(ScoringMath.clamp(21 * (1 - exp(-total / k)), 0, 21))
        return StrainScoreResult(score: score, cardioLoad: ScoringMath.oneDecimal(cardio), muscularLoad: ScoringMath.oneDecimal(muscular), totalLoad: ScoringMath.oneDecimal(total), zones: zones.mapValues(ScoringMath.oneDecimal), label: label(score))
    }
    static func zone(_ reserve: Double) -> (name: String, weight: Double) {
        if reserve >= 0.90 { return ("z5", 9.5) }; if reserve >= 0.80 { return ("z4", 6.5) }
        if reserve >= 0.70 { return ("z3", 3.4) }; if reserve >= 0.60 { return ("z2", 1.8) }
        return reserve >= 0.50 ? ("z1", 0.9) : ("z1", 0)
    }
    static func estimatedReserve(energy: Double, duration: Double) -> Double { duration <= 0 || energy <= 0 ? 0.45 : ScoringMath.clamp(0.45 + energy / duration / 32, 0.45, 0.88) }
    static func muscularLoad(_ workout: Workout, duration: Double) -> Double {
        let type = workout.typeCode == 5 ? 1.25 : workout.typeCode == 6 ? 1.15 : workout.typeCode == 7 ? 0.45 : 0.25
        let kcal = workout.effectiveEnergyKcal <= 0 ? 1 : ScoringMath.clamp(workout.effectiveEnergyKcal / max(duration * 8, 1), 0.65, 1.45)
        return duration * type * kcal
    }
    static func label(_ score: Double) -> String { score >= 20 ? "Very high" : score >= 17 ? "High" : score >= 11 ? "Moderate" : score >= 5 ? "Light" : "Restorative" }
}

enum RecoveryDomainScorer {
    static func calculate(summary: HealthSummary, sleepScore: Int, strainLoad: Double, stress: Int, baselines: HealthBaselines) -> RecoveryResult {
        let hrvAvailable = summary.hrvMs > 0, rhrAvailable = summary.restingHeartBpm > 0
        let hrvBaseline = baselines.hrvLog ?? baselines.hrvMs.map { MetricBaseline(median: log($0.median), mad: $0.mad / $0.median, sampleCount: $0.sampleCount) }
        let hrv = hrvAvailable ? Double(ScoringMath.sigmoid(ScoringMath.robustZ(log(summary.hrvMs), hrvBaseline))) : nil
        let rhr = rhrAvailable ? Double(ScoringMath.sigmoid(-ScoringMath.robustZ(summary.restingHeartBpm, baselines.restingHeartRate))) : nil
        let ratio = (baselines.strainLoad?.median ?? 0) > 0 ? strainLoad / baselines.strainLoad!.median : 1
        let strain = strainBalance(ratio)
        let respiratory = summary.respiratoryRate > 0 ? respiratoryScore(summary.respiratoryRate, baselines) : nil
        let deviation: Double? = summary.wristTemperatureC > 0 && summary.bodyTemperatureC > 0 ? summary.wristTemperatureC - summary.bodyTemperatureC : nil
        let temperature = deviation.map(temperatureScore)
        let contributors: [String: Double?] = ["hrv": hrv, "rhr": rhr, "sleep": summary.hasSleepData ? Double(sleepScore) : nil, "strainBalance": strain, "respiratory": respiratory, "temperature": temperature]
        let weights = ["hrv": 0.35, "rhr": 0.25, "sleep": 0.20, "strainBalance": 0.10, "respiratory": 0.05, "temperature": 0.05]
        var weighted = 0.0, totalWeight = 0.0
        for (key, optional) in contributors { if let value = optional, let weight = weights[key] { weighted += value * weight; totalWeight += weight } }
        var recovery = totalWeight <= 0 ? ScoringMath.clamp((summary.hasSleepData ? Double(sleepScore) : 70) * 0.35 + strain * 0.20 + 45, 0, 70) : weighted / totalWeight
        if !hrvAvailable || !rhrAvailable { recovery = min(recovery, 58) }
        var caps: [String] = []
        if summary.sleepMinutes > 0 && summary.sleepMinutes < 300 { recovery = min(recovery, 45); caps.append("sleep_under_5h") }
        if summary.sleepMinutes > 0 && summary.sleepMinutes < 360 { recovery = min(recovery, 65); caps.append("sleep_under_6h") }
        let baselineRHR = baselines.restingHeartRate?.median ?? 0, baselineHRV = baselines.hrvMs?.median ?? 0
        if baselineRHR > 0 && summary.restingHeartBpm > baselineRHR + 3 { recovery -= 5; caps.append("rhr_plus_3_penalty") }
        if baselineRHR > 0 && summary.restingHeartBpm > baselineRHR + 5 { recovery -= 10; caps.append("rhr_plus_5_penalty") }
        if baselineRHR > 0 && summary.restingHeartBpm > baselineRHR + 8 { recovery = min(recovery, 55); caps.append("rhr_plus_8_cap") }
        if baselineHRV > 0 && baselineRHR > 0 && summary.hrvMs < baselineHRV * 0.8 && summary.restingHeartBpm > baselineRHR + 5 { recovery = min(recovery, 50); caps.append("low_hrv_high_rhr_cap") }
        if (deviation ?? 0) > 0.5 { recovery = min(recovery, 50); caps.append("temperature_deviation_cap") }
        if hrvAvailable && rhrAvailable && summary.sleepMinutes >= 360 && sleepScore >= 60 { recovery = max(recovery, 35) }
        let calibration = ScoringMath.calibration(baselines.primarySampleCount)
        if calibration != .ready { recovery = ScoringMath.clamp(recovery, 20, 82) }
        let score = ScoringMath.score(recovery)
        let available = [hrvAvailable, rhrAvailable, summary.hasSleepData, respiratory != nil, temperature != nil].filter { $0 }.count
        var notes: [String] = []
        if baselineHRV > 0 && summary.hrvMs > 0 { let change = Int(((summary.hrvMs / baselineHRV - 1) * 100).rounded()); notes.append("HRV \(change >= 0 ? "+" : "")\(change)% vs baseline") }
        if baselineRHR > 0 && summary.restingHeartBpm > 0 { let change = Int((summary.restingHeartBpm - baselineRHR).rounded()); notes.append("RHR \(change >= 0 ? "+" : "")\(change) bpm") }
        notes.append(summary.hasSleepData ? "sleep score \(sleepScore)" : "sleep data unavailable")
        if calibration != .ready { notes.append("Quantivita is still learning your baseline") }
        return RecoveryResult(score: score, confidence: ScoringMath.confidence(calibration, available: available, expected: 5), contributors: contributors, notes: notes, label: label(score), summary: "\(score)% recovery. \(notes.joined(separator: " • ")).", capsApplied: caps, calibrationStatus: calibration)
    }
    static func strainBalance(_ ratio: Double) -> Double { ratio >= 0.8 && ratio <= 1.2 ? 100 : ratio > 1.2 && ratio <= 1.5 ? 80 - (ratio - 1.2) * 100 : ratio > 1.5 ? ScoringMath.clamp(50 - (ratio - 1.5) * 80, 0, 50) : ratio < 0.5 ? 75 : 85 }
    static func respiratoryScore(_ value: Double, _ baselines: HealthBaselines) -> Double { guard let baseline = baselines.respiratoryRate, baseline.median > 0 else { return 85 }; return Double(ScoringMath.sigmoid(-ScoringMath.robustZ(value, baseline))) }
    static func temperatureScore(_ deviation: Double) -> Double { abs(deviation) <= 0.2 ? 95 : deviation > 0.5 ? 30 : ScoringMath.clamp(90 - abs(deviation) * 90, 25, 95) }
    static func label(_ score: Int) -> String { score >= 90 ? "Peak recovery" : score >= 75 ? "Good recovery" : score >= 50 ? "Moderate recovery" : score >= 25 ? "Low recovery" : "Poor recovery" }
}

enum DailyScoringEngine {
    static func calculate(summary: HealthSummary, workouts: [Workout], stressScore: Int = 14) -> DailyScores {
        let calendar = Calendar.current
        let today = workouts.filter { calendar.isDateInToday($0.startTime) }
        let strain = StrainScorer.calculate(workouts: today, restingHeartRate: summary.restingHeartBpm)
        let efficiency = summary.sleepInBedMinutes > 0 ? ScoringMath.clamp(summary.sleepMinutes / summary.sleepInBedMinutes, 0, 1) : summary.sleepMinutes > 0 ? 1 : nil
        let sleep = SleepScorer.calculate(duration: summary.sleepMinutes, efficiency: efficiency, awake: summary.sleepAwakeMinutes, rem: summary.sleepREMMinutes, deep: summary.sleepDeepMinutes)
        let deviation = summary.wristTemperatureC > 0 && summary.bodyTemperatureC > 0 ? summary.wristTemperatureC - summary.bodyTemperatureC : 0
        let baselines = BaselineScorer.fromToday(hrv: summary.hrvMs, restingHeartRate: summary.restingHeartBpm, sleepMinutes: summary.sleepMinutes, sleepEfficiency: efficiency ?? 0, strainLoad: strain.totalLoad, stress: Double(stressScore), respiratoryRate: summary.respiratoryRate, temperatureDeviation: deviation)
        let recovery = RecoveryDomainScorer.calculate(summary: summary, sleepScore: sleep.score, strainLoad: strain.totalLoad, stress: stressScore, baselines: baselines)
        let need = sleepNeed(actual: summary.sleepMinutes, strainPercent: strain.percent)
        let battery = bodyBattery(recovery: recovery.score, sleep: sleep.score, strain: strain.percent, stress: stressScore, activeEnergy: summary.activeEnergyKcal, steps: summary.steps)
        return DailyScores(sleep: sleep, strain: strain, recovery: recovery, sleepNeed: need, bodyBattery: battery, stressScore: stressScore)
    }

    static func sleepNeed(actual: Double, strainPercent: Double, baseline: Double = 480) -> SleepNeedResult {
        let ratio = ScoringMath.clamp(strainPercent / 100, 0, 1), strain = 90 * ratio * ratio
        let debt = baseline - actual > 0 ? ScoringMath.clamp((baseline - actual) * 0.5, 0, 120) : 0
        let need = ScoringMath.clamp(baseline + strain + debt, 390, 660), performance = need <= 0 ? 0 : ScoringMath.score(actual / need * 100)
        var parts: [String] = []; if strain >= 10 { parts.append("\(Int(strain.rounded()))m extra from strain") }; if debt >= 10 { parts.append("\(Int(debt.rounded()))m sleep debt carried into target") }; if parts.isEmpty { parts.append("baseline sleep need only") }
        return SleepNeedResult(needMinutes: need, performanceScore: performance, strainNeedMinutes: strain, debtMinutes: debt, summary: "\(performance)% sleep performance: \(parts.joined(separator: " • ")).")
    }

    static func bodyBattery(recovery: Int, sleep: Int, strain: Double, stress: Int, activeEnergy: Double, steps: Double) -> BodyBatteryResult {
        let activityDrain = ScoringMath.clamp(activeEnergy / 18, 0, 28), stepDrain = ScoringMath.clamp(steps / 12000 * 8, 0, 10), strainDrain = ScoringMath.clamp(strain * 0.32, 0, 34), stressDrain = ScoringMath.clamp(Double(stress) * 0.22, 0, 24), rest = stress <= 12 ? 8.0 : stress <= 20 ? 3 : 0
        let score = ScoringMath.score(Double(recovery) * 0.7 + Double(sleep) * 0.3 - activityDrain - stepDrain - strainDrain - stressDrain + rest)
        let title = score >= 75 ? "Strong energy reserve" : score >= 50 ? "Steady energy reserve" : "Low energy reserve"
        let band = score >= 75 ? "Recovery and sleep are supporting the day so far." : score >= 50 ? "You have usable capacity, but strain and stress still matter." : score >= 30 ? "Keep intensity modest and protect recovery windows." : "The day is asking for rest, food, sleep, or a gentler load."
        var factors = [BodyBatteryFactor(label: "Recovery charge", points: Double(recovery) * 0.7, detail: "\(recovery)% recovery × 0.70"), BodyBatteryFactor(label: "Sleep charge", points: Double(sleep) * 0.3, detail: "\(sleep) sleep score × 0.30"), BodyBatteryFactor(label: "Active burn drain", points: -activityDrain, detail: "\(Int(activeEnergy.rounded())) active kcal"), BodyBatteryFactor(label: "Movement drain", points: -stepDrain, detail: "\(Int(steps.rounded())) steps today"), BodyBatteryFactor(label: "Strain drain", points: -strainDrain, detail: "\(Int(strain.rounded()))% daily strain"), BodyBatteryFactor(label: "Stress drain", points: -stressDrain, detail: "\(stress) stress score")]
        if rest > 0 { factors.append(BodyBatteryFactor(label: "Low-stress recharge", points: rest, detail: "Quiet periods add reserve back")) }
        return BodyBatteryResult(score: score, title: title, summary: "\(score)/100 energy reserve. \(band)", factors: factors)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
