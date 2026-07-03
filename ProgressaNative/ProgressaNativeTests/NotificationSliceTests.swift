import XCTest
@testable import ProgressaNative

final class NotificationSliceTests: XCTestCase {
    @MainActor
    func testConfigureLoadsInboxAndPreferences() async {
        let service = NotificationServiceFake()
        service.notifications = [Self.notification()]
        service.storedPreferences = .init(newFollowers: false, likes: true, comments: false)
        let model = ProgressaNotificationModel(service: service)

        await model.configure(Self.session)

        XCTAssertEqual(model.notifications.map(\.id), ["notification-1"])
        XCTAssertFalse(model.preferences.newFollowers)
        XCTAssertTrue(model.preferences.likes)
        XCTAssertFalse(model.preferences.comments)
    }

    @MainActor
    func testMarkReadUpdatesInboxAndService() async {
        let service = NotificationServiceFake()
        service.notifications = [Self.notification()]
        let model = ProgressaNotificationModel(service: service)
        await model.configure(Self.session)

        await model.markRead(model.notifications[0])

        XCTAssertNotNil(model.notifications[0].readAt)
        XCTAssertEqual(service.markedReadIDs, ["notification-1"])
    }

    @MainActor
    func testRespondRemovesFollowRequestAndSendsDecision() async {
        let service = NotificationServiceFake()
        service.notifications = [Self.notification(type: "follow_request")]
        let model = ProgressaNotificationModel(service: service)
        await model.configure(Self.session)

        await model.respond(model.notifications[0], accept: true)

        XCTAssertTrue(model.notifications.isEmpty)
        XCTAssertEqual(service.responses.first?.0, "notification-1")
        XCTAssertEqual(service.responses.first?.1, true)
    }

    @MainActor
    func testSavePersistsCurrentPreferences() async {
        let service = NotificationServiceFake()
        let model = ProgressaNotificationModel(service: service)
        await model.configure(Self.session)
        model.preferences = .init(newFollowers: false, likes: false, comments: true)

        await model.savePreferences()

        XCTAssertEqual(service.savedPreferences, model.preferences)
    }

    private static let session = ProgressaSession(
        accessToken: "access", refreshToken: "refresh", userId: "user-1",
        expiresAt: .distantFuture, email: "user@example.com"
    )

    private static func notification(type: String = "post_like") -> ProgressaNotification {
        .init(
            id: "notification-1", actorId: "actor-1", type: type, postId: "post-1",
            commentId: nil, message: "liked your post", createdAt: .now, readAt: nil,
            actorName: "Alex", actorHandle: "alex", actorAvatarPath: nil
        )
    }
}

private final class NotificationServiceFake: ProgressaNotificationServing {
    var notifications: [ProgressaNotification] = []
    var storedPreferences = ProgressaNotificationPreferences()
    var markedReadIDs: [String] = []
    var responses: [(String, Bool)] = []
    var savedPreferences: ProgressaNotificationPreferences?

    func list(session: ProgressaSession) async throws -> [ProgressaNotification] { notifications }
    func markRead(id: String, session: ProgressaSession) async throws { markedReadIDs.append(id) }
    func respond(notification: ProgressaNotification, accept: Bool, session: ProgressaSession) async throws {
        responses.append((notification.id, accept))
    }
    func preferences(session: ProgressaSession) async throws -> ProgressaNotificationPreferences { storedPreferences }
    func save(_ value: ProgressaNotificationPreferences, session: ProgressaSession) async throws { savedPreferences = value }
}
