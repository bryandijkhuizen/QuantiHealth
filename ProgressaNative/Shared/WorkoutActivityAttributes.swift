import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var startedAt: Date
        var loggedSets: Int
        var exerciseName: String?
        var endedAt: Date?
    }

    var workoutID: String
    var url: URL { URL(string: "progressa://workout/\(workoutID)")! }
}
