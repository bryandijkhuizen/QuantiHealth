import Foundation

struct ProgressaNotification: Identifiable, Hashable {
    let id: String
    let actorId: String?
    let type: String
    let postId: String?
    let commentId: String?
    let message: String
    let createdAt: Date
    var readAt: Date?
    var actorName: String
    var actorHandle: String?
    var actorAvatarPath: String?
    var isUnread: Bool { readAt == nil }
    var isFollowRequest: Bool { type == "follow_request" }
}

struct ProgressaNotificationPreferences: Equatable {
    var newFollowers = true
    var likes = true
    var comments = true
}
