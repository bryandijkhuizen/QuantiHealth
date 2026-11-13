import Foundation

struct ProgressaSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let expiresAt: Date
    var email: String? = nil
    var provider: String? = nil

    var isAppleUser: Bool { provider?.lowercased() == "apple" }
}

struct ProgressaProfile: Codable, Equatable {
    let userId: String
    var fullName: String?
    var country: String?
    var birthdate: Date?
    var heightCm: Double? = nil
    var unitSystem: String? = nil
    var sex: String? = nil
    var profileVisibility: String? = nil
    var handle: String? = nil
    var avatarPath: String? = nil

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case fullName = "full_name"
        case country, birthdate
        case heightCm = "height_cm"
        case unitSystem = "unit_system"
        case sex
        case profileVisibility = "profile_visibility"
        case handle
        case avatarPath = "avatar_path"
    }

    func isComplete(appleUser: Bool) -> Bool {
        let hasName = !(fullName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasCountry = !(country?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return (appleUser || hasName) && hasCountry && birthdate != nil
    }
}

enum MeasurementUnitSystem: String, CaseIterable {
    case metric, imperial

    func displayValue(_ stored: Double, type: ProgressaMeasurementType) -> Double {
        switch (self, type.kind) {
        case (.imperial, .weight): return stored * 2.204_622_621_8
        case (.imperial, .circumference): return stored / 2.54
        default: return stored
        }
    }

    func storageValue(_ displayed: Double, type: ProgressaMeasurementType) -> Double {
        switch (self, type.kind) {
        case (.imperial, .weight): return displayed / 2.204_622_621_8
        case (.imperial, .circumference): return displayed * 2.54
        default: return displayed
        }
    }

    func unit(for type: ProgressaMeasurementType) -> String {
        switch type.kind {
        case .percent: return "%"
        case .weight: return self == .imperial ? "lb" : "kg"
        case .circumference: return self == .imperial ? "in" : "cm"
        }
    }
}

enum ProgressaMeasurementKind { case weight, percent, circumference }

enum ProgressaMeasurementType: String, Codable, CaseIterable, Identifiable {
    case weight = "WEIGHT", bodyFat = "BODY_FAT", chest = "CHEST", waist = "WAIST"
    case leftArm = "LEFT_ARM", rightArm = "RIGHT_ARM", hips = "HIPS"
    case leftThigh = "LEFT_THIGH", rightThigh = "RIGHT_THIGH", neck = "NECK"
    var id: String { rawValue }
    var kind: ProgressaMeasurementKind {
        switch self { case .weight: return .weight; case .bodyFat: return .percent; default: return .circumference }
    }
    var title: String {
        switch self {
        case .weight: return "Weight"; case .bodyFat: return "Body fat"; case .chest: return "Chest"
        case .waist: return "Waist"; case .leftArm: return "Left arm"; case .rightArm: return "Right arm"
        case .hips: return "Hips"; case .leftThigh: return "Left thigh"; case .rightThigh: return "Right thigh"
        case .neck: return "Neck"
        }
    }
    var displayRange: ClosedRange<Double> {
        switch self {
        case .weight: return 30...200.9
        case .bodyFat: return 3...60.9
        case .leftArm, .rightArm: return 20...60.9
        default: return 40...170.9
        }
    }
}

struct ProgressaMeasurement: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    var measuredAt: Date
    var type: ProgressaMeasurementType
    var value: Double
    var note: String?
    enum CodingKeys: String, CodingKey {
        case id, type, value, note
        case userId = "user_id"
        case measuredAt = "measured_at"
    }
}

enum ProgressaWeightType: String, Codable { case standard, bodyweight, assisted }

struct ProgressaSetStat: Identifiable, Equatable {
    let id: String
    let workoutId: String
    let exerciseId: String
    let exerciseName: String
    let weightType: ProgressaWeightType
    let weightKg: Double?
    let reps: Int?
    let createdAt: Date
    let workoutCreatedAt: Date?
    var effectiveDate: Date { workoutCreatedAt ?? createdAt }
}

struct ProgressaCardioSession: Identifiable, Equatable {
    let workoutId: String
    let date: Date
    let activityType: String
    let title: String
    let durationSeconds: Int?
    let distanceMeters: Double?
    let calories: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let location: String?
    var id: String { workoutId }
}

struct ProgressaPersonalRecord: Identifiable, Equatable {
    let exerciseId: String
    let exerciseName: String
    let value: Double
    let reps: Int
    let weightType: ProgressaWeightType
    let date: Date
    var id: String { exerciseId }
}

struct ProgressaStatsSummary: Equatable {
    let workoutCount: Int
    let setCount: Int
    let repCount: Int
    let volumeKg: Double
    let latestTraining: Date?
    let personalRecords: [ProgressaPersonalRecord]

    static func calculate(_ rows: [ProgressaSetStat]) -> ProgressaStatsSummary {
        let workouts = Set(rows.map(\.workoutId).filter { !$0.isEmpty }).count
        let reps = rows.reduce(0) { $0 + ($1.reps ?? 0) }
        let volume = rows.reduce(0.0) { result, row in
            guard row.weightType != .bodyweight else { return result }
            return result + (row.weightKg ?? 0) * Double(row.reps ?? 0)
        }
        var records: [String: ProgressaPersonalRecord] = [:]
        for row in rows {
            let candidate = row.weightType == .bodyweight ? Double(row.reps ?? 0) : (row.weightKg ?? -.infinity)
            guard candidate.isFinite else { continue }
            if records[row.exerciseId]?.value ?? -.infinity < candidate {
                records[row.exerciseId] = ProgressaPersonalRecord(
                    exerciseId: row.exerciseId, exerciseName: row.exerciseName, value: candidate,
                    reps: row.reps ?? 0, weightType: row.weightType, date: row.effectiveDate
                )
            }
        }
        return ProgressaStatsSummary(
            workoutCount: workouts, setCount: rows.count, repCount: reps, volumeKg: volume,
            latestTraining: rows.map(\.effectiveDate).max(),
            personalRecords: records.values.sorted { $0.date > $1.date }
        )
    }
}

struct ProgressaWorkout: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var createdAt: Date
    var source: String = "manual"
    var location: String?
    var exercises: [ProgressaExercise]
    var startedAt: Date? = nil
    var endedAt: Date? = nil
    var isInProgress: Bool { startedAt != nil && endedAt == nil }
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
}

struct ProgressaExercise: Identifiable, Hashable, Codable {
    /// The persistent workout_exercise_blocks id. A workout can contain the same exercise more than once.
    let id: String
    let exerciseId: String
    var name: String
    var muscleGroup: String?
    var weightType: ProgressaWeightType = .standard
    var sortOrder: Int = 0
    var sets: [ProgressaWorkoutSet]
    var sequenceID: String? = nil
    var sequenceRound: Int? = nil

    init(
        id: String, exerciseId: String? = nil, name: String, muscleGroup: String? = nil,
        weightType: ProgressaWeightType = .standard, sortOrder: Int = 0,
        sets: [ProgressaWorkoutSet]
    ) {
        self.id = id
        self.exerciseId = exerciseId ?? id
        self.name = name
        self.muscleGroup = muscleGroup
        self.weightType = weightType
        self.sortOrder = sortOrder
        self.sets = sets
    }
}

struct ProgressaWorkoutSet: Identifiable, Hashable, Codable {
    let id: String
    var baseWeightKg: Double? = nil
    var addedWeightKg: Double? { weightKg.map { $0 - (baseWeightKg ?? 0) } }
    var weightKg: Double?
    var reps: Int?
    var rir: Double?
    var side: String?
    var isWarmup: Bool
    var createdAt: Date = .now
}

struct ProgressaExerciseLibraryItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let muscleGroup: String?
    let weightType: ProgressaWeightType
    let isBuiltin: Bool
}

struct ProgressaSetInput: Equatable {
    var weightKg: Double?
    var reps: Int?
    var rir: Double?
    var side: String?
    var isWarmup = false

    var isValidForEntry: Bool {
        guard let reps, reps > 0 else { return false }
        if let weightKg, weightKg < 0 { return false }
        if let rir, !(0...10).contains(rir) { return false }
        return side == nil || side == "L" || side == "R"
    }
}

struct ProgressaExerciseInput: Identifiable, Equatable {
    let id: UUID
    let exercise: ProgressaExerciseLibraryItem
    var sets: [ProgressaSetInput]

    init(id: UUID = UUID(), exercise: ProgressaExerciseLibraryItem, sets: [ProgressaSetInput]) {
        self.id = id
        self.exercise = exercise
        self.sets = sets
    }
}

struct CachedWorkouts: Codable, Equatable {
    let workouts: [ProgressaWorkout]
    let savedAt: Date
}

enum WorkoutSyncState: Equatable {
    case idle
    case fresh(Date)
    case cached(Date?)
}

struct QuantivitaConnectRequest: Identifiable, Equatable {
    let redirectURI: URL
    let state: String
    let scope: String
    var id: String { state }

    init?(url: URL) {
        guard url.scheme == "progressa", url.host == "quantivita-connect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let redirect = components.queryItems?.first(where: { $0.name == "redirect_uri" })?.value,
              let redirectURI = URL(string: redirect),
              redirectURI.scheme == "quantivita", redirectURI.host == "quantivita.app",
              redirectURI.path == "/progressa-auth",
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
              !state.isEmpty else { return nil }
        self.redirectURI = redirectURI
        self.state = state
        self.scope = components.queryItems?.first(where: { $0.name == "scope" })?.value ?? "workouts:read"
    }
}
