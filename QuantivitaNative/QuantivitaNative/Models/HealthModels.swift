import Foundation

struct HealthSummary: Codable, Equatable {
    var sleepMinutes = 0.0
    var sleepREMMinutes = 0.0
    var sleepCoreMinutes = 0.0
    var sleepDeepMinutes = 0.0
    var sleepAwakeMinutes = 0.0
    var sleepInBedMinutes = 0.0
    var hrvMs = 0.0
    var restingHeartBpm = 0.0
    var respiratoryRate = 0.0
    var oxygenSaturation = 0.0
    var activeEnergyKcal = 0.0
    var basalEnergyKcal = 0.0
    var dietaryEnergyKcal = 0.0
    var dietaryWaterMl = 0.0
    var dietaryCarbohydratesG = 0.0
    var dietaryProteinG = 0.0
    var dietaryFatG = 0.0
    var steps = 0.0
    var bodyTemperatureC = 0.0
    var wristTemperatureC = 0.0
    var bodyMassKg = 0.0
    var heightCm = 0.0
    var bodyFatPercent = 0.0
    var birthYear = 0
    var birthMonth = 0
    var birthDay = 0
    var biologicalSex = 0
    var vo2MaxSamples: [VO2MaxSample]?

    var hasSleepData: Bool { sleepMinutes > 0 }
    var hasAnyHealthData: Bool {
        steps > 0 || activeEnergyKcal > 0 || hrvMs > 0 || restingHeartBpm > 0 ||
        sleepMinutes > 0 || bodyMassKg > 0 || dietaryEnergyKcal > 0
    }
}

struct VO2MaxSample: Codable, Equatable {
    let time: Date
    let millilitersPerKilogramPerMinute: Double
}

struct WeightSample: Codable, Identifiable, Equatable {
    let date: Date
    let kg: Double
    var id: Date { date }
}

struct Workout: Codable, Identifiable, Hashable {
    let id: String
    var source = "healthkit"
    var externalWorkoutId: String?
    var title: String
    var startTime: Date
    var durationMinutes: Double
    var energyKcal: Double
    var totalEnergyKcal: Double
    var distanceMeters: Double
    var elevationGainMeters: Double
    var averageHeartRate: Double
    var maxHeartRate: Double
    var typeCode: Int
    var hasRoute: Bool
    var sourceName: String?
    var sourceBundleIdentifier: String?
    var progressaWorkoutTitle: String?
    var healthActivityLink: HealthActivityLink?
    var progressaDetails: ProgressaDetails?
    var telemetry: WorkoutTelemetry?

    var isProgressa: Bool { source == "progressa" }
    var effectiveDurationMinutes: Double {
        guard durationMinutes <= 0, let details = progressaDetails else { return durationMinutes }
        return min(180, Double(details.totalSets) * 2.5 + Double(details.exerciseCount) * 4)
    }
    var effectiveEnergyKcal: Double {
        guard energyKcal <= 0, let details = progressaDetails else { return energyKcal }
        return min(900, effectiveDurationMinutes * 4.5 + details.totalVolumeKg / 120)
    }

    enum CodingKeys: String, CodingKey {
        case id, source, externalWorkoutId, title, startTime, durationMinutes, energyKcal
        case totalEnergyKcal, distanceMeters, elevationGainMeters, averageHeartRate
        case maxHeartRate, typeCode, hasRoute, sourceName, sourceBundleIdentifier
        case progressaWorkoutTitle, healthActivityLink, progressaDetails, telemetry
    }

    init(
        id: String, source: String = "healthkit", externalWorkoutId: String? = nil,
        title: String, startTime: Date, durationMinutes: Double, energyKcal: Double,
        totalEnergyKcal: Double = 0, distanceMeters: Double = 0,
        elevationGainMeters: Double = 0, averageHeartRate: Double = 0,
        maxHeartRate: Double = 0, typeCode: Int = 0, hasRoute: Bool = false,
        sourceName: String? = nil, sourceBundleIdentifier: String? = nil,
        progressaWorkoutTitle: String? = nil, healthActivityLink: HealthActivityLink? = nil,
        progressaDetails: ProgressaDetails? = nil
    ) {
        self.id = id
        self.source = source
        self.externalWorkoutId = externalWorkoutId
        self.title = title
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.energyKcal = energyKcal
        self.totalEnergyKcal = totalEnergyKcal
        self.distanceMeters = distanceMeters
        self.elevationGainMeters = elevationGainMeters
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.typeCode = typeCode
        self.hasRoute = hasRoute
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.progressaWorkoutTitle = progressaWorkoutTitle
        self.healthActivityLink = healthActivityLink
        self.progressaDetails = progressaDetails
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? "healthkit"
        externalWorkoutId = try values.decodeIfPresent(String.self, forKey: .externalWorkoutId)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "Workout"
        startTime = try values.decodeFlexibleDate(forKey: .startTime)
        durationMinutes = values.decodeLossyDouble(forKey: .durationMinutes)
        energyKcal = values.decodeLossyDouble(forKey: .energyKcal)
        totalEnergyKcal = values.decodeLossyDouble(forKey: .totalEnergyKcal)
        distanceMeters = values.decodeLossyDouble(forKey: .distanceMeters)
        elevationGainMeters = values.decodeLossyDouble(forKey: .elevationGainMeters)
        averageHeartRate = values.decodeLossyDouble(forKey: .averageHeartRate)
        maxHeartRate = values.decodeLossyDouble(forKey: .maxHeartRate)
        typeCode = (try? values.decode(Int.self, forKey: .typeCode)) ?? 0
        hasRoute = (try? values.decode(Bool.self, forKey: .hasRoute)) ?? false
        sourceName = try values.decodeIfPresent(String.self, forKey: .sourceName)
        sourceBundleIdentifier = try values.decodeIfPresent(String.self, forKey: .sourceBundleIdentifier)
        progressaWorkoutTitle = try values.decodeIfPresent(String.self, forKey: .progressaWorkoutTitle)
        healthActivityLink = try values.decodeIfPresent(HealthActivityLink.self, forKey: .healthActivityLink)
        progressaDetails = try values.decodeIfPresent(ProgressaDetails.self, forKey: .progressaDetails)
        telemetry = try values.decodeIfPresent(WorkoutTelemetry.self, forKey: .telemetry)
    }
}

/// Optional measured data; absent permissions/data remain absent rather than zero.
struct WorkoutTelemetry: Codable, Hashable {
    struct HeartRate: Codable, Hashable { let time: String; let bpm: Double }
    struct Speed: Codable, Hashable { let time: String; let metersPerSecond: Double }
    struct Event: Codable, Hashable { let type: String; let startTime: String; let endTime: String }
    struct Split: Codable, Hashable { let distanceMeters: Double; let durationSeconds: Double }
    var heartRateSamples: [HeartRate] = []
    var speedSamples: [Speed] = []
    var workoutEvents: [Event] = []
    var kilometerSplits: [Split] = []
    var splitMethod: String?
    var cadenceStepsPerMinute: Double?
    var runningPowerWatts: Double?
    var runningStrideLengthMeters: Double?
    var runningGroundContactTimeMilliseconds: Double?
    var runningVerticalOscillationMeters: Double?
}

struct HealthActivityLink: Codable, Hashable {
    let healthStart: String
    let healthEnd: String
    let activityType: String
    let durationSeconds: Double?
}

struct ProgressaDetails: Codable, Hashable {
    var exerciseCount: Int
    var totalSets: Int
    var totalVolumeKg: Double
    var hasVolumeData: Bool
    var exercises: [ProgressaExercise]
}

struct ProgressaExercise: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var muscleGroup: String?
    var sets: [ProgressaSet]
}

struct ProgressaSet: Codable, Hashable, Identifiable {
    var id: String { "\(createdAt ?? "")-\(weightKg ?? 0)-\(reps ?? 0)-\(side ?? "")" }
    var weightKg: Double?
    var reps: Int?
    var rir: Double?
    var side: String?
    var isWarmup: Bool?
    var createdAt: String?
}

struct RecoveryResult: Equatable {
    let score: Int
    let confidence: Double
    let contributors: [String: Double?]
    let notes: [String]
    var label = ""
    var summary = ""
    var capsApplied: [String] = []
    var calibrationStatus: CalibrationStatus = .insufficientData
}

private extension KeyedDecodingContainer {
    func decodeLossyDouble(forKey key: Key) -> Double {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) { return Double(value) ?? 0 }
        return 0
    }

    func decodeFlexibleDate(forKey key: Key) throws -> Date {
        if let seconds = try? decode(Double.self, forKey: key) {
            return Self.date(fromNumericSeconds: seconds)
        }
        let raw = try decode(String.self, forKey: key)
        if let seconds = Double(raw) {
            return Self.date(fromNumericSeconds: seconds)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) { return date }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Unsupported date: \(raw)")
    }

    private static func date(fromNumericSeconds seconds: Double) -> Date {
        let normalized = seconds > 10_000_000_000 ? seconds / 1000 : seconds
        if normalized < Date(timeIntervalSinceReferenceDate: 0).timeIntervalSince1970 {
            return Date(timeIntervalSinceReferenceDate: normalized)
        }
        return Date(timeIntervalSince1970: normalized)
    }
}
