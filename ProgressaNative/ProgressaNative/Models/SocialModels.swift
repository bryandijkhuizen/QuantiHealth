import Foundation

enum FeedMode: String, CaseIterable, Codable, Identifiable {
    case following = "Following"
    case recent = "Recent"
    case popular = "Popular"
    var id: String { rawValue }
}

struct SocialPost: Identifiable, Hashable, Codable {
    let id: String
    let authorId: String
    var text: String?
    var visibility: String
    var createdAt: Date
    var authorName: String
    var authorHandle: String? = nil
    var avatarPath: String? = nil
    var type: String
    var workoutTitle: String? = nil
    var workoutShare: WorkoutShareSnapshot? = nil
    var likeCount: Int
    var commentsCount: Int
}

struct RouteCoordinate: Hashable, Codable {
    var latitude: Double
    var longitude: Double
}

struct WorkoutShareSnapshot: Hashable, Codable {
    var workoutId: String
    var workoutTitle: String
    var workoutCreatedAt: Date?
    var groups: [WorkoutShareGroup]
    var activityType: String?
    var durationSeconds: Double?
    var calories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var location: String?
    var distanceMeters: Double?
    var routePoints: [RouteCoordinate] = []

    var totalSets: Int { groups.reduce(0) { $0 + $1.sets.count } }
    var isCardio: Bool {
        guard groups.isEmpty, let key = activityType?.lowercased(), !key.isEmpty else { return false }
        return !key.contains("strength") && !key.contains("weight training")
    }
}

struct WorkoutShareGroup: Hashable, Codable, Identifiable {
    var id: String
    var exerciseName: String
    var sets: [WorkoutShareSet]
}

struct WorkoutShareSet: Hashable, Codable {
    var weightKg: Double?
    var reps: Int?
}

struct SocialUser: Identifiable, Hashable, Codable {
    let userId: String
    var fullName: String
    var handle: String? = nil
    var country: String? = nil
    var avatarPath: String? = nil
    var profileVisibility: String
    var id: String { userId }
}

struct SocialComment: Identifiable, Hashable {
    let id: String
    let postId: String
    let userId: String
    var parentId: String?
    var text: String
    let createdAt: Date
    var editedAt: Date?
    var authorName: String
    var authorHandle: String?
    var avatarPath: String?
    var likeCount: Int
    var isLiked: Bool
}

struct CachedFeed: Codable, Equatable {
    let posts: [SocialPost]
    let savedAt: Date
}

enum FeedSyncState: Equatable {
    case idle
    case fresh(Date)
    case cached(Date?)
}
