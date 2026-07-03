import Foundation
import HealthKit

enum RecordingActivity: String, CaseIterable, Identifiable {
    case run = "Run"
    case walk = "Walk"
    case cycle = "Cycle"
    case hike = "Hike"

    var id: String { rawValue }

    var hkType: HKWorkoutActivityType {
        switch self {
        case .run: return .running
        case .walk: return .walking
        case .cycle: return .cycling
        case .hike: return .hiking
        }
    }

    var systemImage: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .cycle: return "bicycle"
        case .hike: return "figure.hiking"
        }
    }
}

struct ProgressaHealthSession: Identifiable, Hashable {
    let workoutUUID: UUID
    let start: Date
    let end: Date
    let activityType: String
    let calories: Double?
    let distanceMeters: Double?
    var id: String { workoutUUID.uuidString }
    var durationSeconds: Int { max(0, Int(end.timeIntervalSince(start))) }
}

struct ProgressaHealthMetadata: Equatable {
    let workoutId: String
    let activityType: String
    let start: Date
    let end: Date
    let durationSeconds: Int
    let calories: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let distanceMeters: Double?
    let location: String?
}
