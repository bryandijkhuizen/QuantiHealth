import XCTest
@testable import ProgressaNative

@MainActor
final class SocialSliceTests: XCTestCase {
    private let session = ProgressaSession(
        accessToken: "access", refreshToken: "refresh", userId: "me", expiresAt: .distantFuture
    )

    func testCacheIsIsolatedByAccountAndMode() throws {
        let cache = SocialCache(directory: temporaryDirectory())
        let post = samplePost()
        try cache.save([post], userId: "me", mode: .following, at: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(cache.load(userId: "me", mode: .following)?.posts, [post])
        XCTAssertNil(cache.load(userId: "other", mode: .following))
        XCTAssertNil(cache.load(userId: "me", mode: .popular))
    }

    func testOfflineRefreshRestoresCachedFeed() async throws {
        let cache = SocialCache(directory: temporaryDirectory())
        let savedAt = Date(timeIntervalSince1970: 20)
        try cache.save([samplePost()], userId: session.userId, mode: .following, at: savedAt)
        let service = FakeSocialService(); service.error = ProgressaClientError.invalidResponse
        let model = SocialModel(service: service, cache: cache)

        await model.configure(session: session)

        XCTAssertEqual(model.posts, [samplePost()])
        XCTAssertEqual(model.syncState, .cached(savedAt))
    }

    func testFollowAndOwnerMutationRules() async {
        let service = FakeSocialService()
        let model = SocialModel(service: service, cache: SocialCache(directory: temporaryDirectory()))
        await model.configure(session: session)
        let user = SocialUser(userId: "other", fullName: "Other", profileVisibility: "public")

        await model.toggleFollow(user)
        XCTAssertEqual(model.followStatuses[user.id], "accepted")
        await model.toggleFollow(user)
        XCTAssertEqual(model.followStatuses[user.id], "none")

        var foreign = samplePost(); foreign = SocialPost(
            id: foreign.id, authorId: "other", text: foreign.text, visibility: foreign.visibility,
            createdAt: foreign.createdAt, authorName: foreign.authorName, type: foreign.type,
            likeCount: 0, commentsCount: 0
        )
        let changed = await model.updatePost(foreign, text: "No")
        XCTAssertFalse(changed)
        XCTAssertEqual(service.updateCalls, 0)
    }

    func testLikeAndCommentMutationsUpdateFeedState() async {
        let service = FakeSocialService(); service.posts = [samplePost()]
        let model = SocialModel(service: service, cache: SocialCache(directory: temporaryDirectory()))
        await model.configure(session: session)
        let post = model.posts[0]

        await model.toggleLike(post)
        XCTAssertTrue(model.likedPostIDs.contains(post.id))
        XCTAssertEqual(model.posts[0].likeCount, 1)
        XCTAssertEqual(service.likeChanges, [true])

        let created = await model.createComment(postId: post.id, text: "Nice")
        XCTAssertTrue(created)
        XCTAssertEqual(model.posts[0].commentsCount, 1)
        XCTAssertEqual(service.createdComments, ["Nice"])
    }

    func testCommentLikeTogglesStateAndCallsService() async throws {
        let service = FakeSocialService(); service.posts = [samplePost()]
        service.commentList = [SocialComment(
            id: "c1", postId: "post", userId: "other", parentId: nil, text: "Hi",
            createdAt: Date(timeIntervalSince1970: 2), editedAt: nil, authorName: "Other",
            authorHandle: "other", avatarPath: nil, likeCount: 0, isLiked: false
        )]
        let model = SocialModel(service: service, cache: SocialCache(directory: temporaryDirectory()))
        await model.configure(session: session)
        await model.loadComments(postId: "post")

        let comment = try XCTUnwrap(model.commentsByPost["post"]?.first)
        await model.toggleCommentLike(comment)

        XCTAssertEqual(model.commentsByPost["post"]?.first?.isLiked, true)
        XCTAssertEqual(model.commentsByPost["post"]?.first?.likeCount, 1)
        XCTAssertEqual(service.commentLikeChanges, [true])
    }

    func testFollowersAndLikersListsResolveThroughService() async {
        let service = FakeSocialService()
        service.followerList = [SocialUser(userId: "u1", fullName: "Ann", profileVisibility: "public")]
        service.likerList = [SocialUser(userId: "u2", fullName: "Bob", profileVisibility: "public")]
        let model = SocialModel(service: service, cache: SocialCache(directory: temporaryDirectory()))
        await model.configure(session: session)

        let followers = await model.followers(of: "me")
        let likers = await model.likers(of: samplePost())

        XCTAssertEqual(followers.map(\.fullName), ["Ann"])
        XCTAssertEqual(likers.map(\.fullName), ["Bob"])
    }

    private func samplePost() -> SocialPost {
        SocialPost(
            id: "post", authorId: "me", text: "Hello", visibility: "public",
            createdAt: Date(timeIntervalSince1970: 1), authorName: "Me", type: "post",
            likeCount: 0, commentsCount: 0
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private final class FakeSocialService: SocialServing {
    var posts: [SocialPost] = []
    var commentList: [SocialComment] = []
    var error: Error?
    var updateCalls = 0
    var likeChanges: [Bool] = []
    var commentLikeChanges: [Bool] = []
    var createdComments: [String] = []
    var followerList: [SocialUser] = []
    var followingList: [SocialUser] = []
    var likerList: [SocialUser] = []

    func fetchFeed(_ mode: FeedMode, session: ProgressaSession) async throws -> [SocialPost] { if let error { throw error }; return posts }
    func createPost(text: String, visibility: String, session: ProgressaSession) async throws { if let error { throw error } }
    func updatePost(id: String, text: String, session: ProgressaSession) async throws { updateCalls += 1; if let error { throw error } }
    func deletePost(id: String, session: ProgressaSession) async throws { if let error { throw error } }
    func searchUsers(_ query: String, session: ProgressaSession) async throws -> [SocialUser] { if let error { throw error }; return [] }
    func follow(_ userId: String, session: ProgressaSession) async throws -> String { if let error { throw error }; return "accepted" }
    func unfollow(_ userId: String, session: ProgressaSession) async throws { if let error { throw error } }
    func followStatus(_ userId: String, session: ProgressaSession) async throws -> String { "none" }
    func followers(_ userId: String, session: ProgressaSession) async throws -> [SocialUser] { if let error { throw error }; return followerList }
    func following(_ userId: String, session: ProgressaSession) async throws -> [SocialUser] { if let error { throw error }; return followingList }
    func postLikers(_ postId: String, session: ProgressaSession) async throws -> [SocialUser] { if let error { throw error }; return likerList }
    func profilePosts(_ userId: String, session: ProgressaSession) async throws -> [SocialPost] { [] }
    func isPostLiked(_ postId: String, session: ProgressaSession) async throws -> Bool { false }
    func setPostLiked(_ liked: Bool, postId: String, session: ProgressaSession) async throws { likeChanges.append(liked) }
    func setCommentLiked(_ liked: Bool, commentId: String, session: ProgressaSession) async throws { commentLikeChanges.append(liked) }
    func comments(_ postId: String, session: ProgressaSession) async throws -> [SocialComment] { commentList }
    func createComment(postId: String, text: String, parentId: String?, session: ProgressaSession) async throws { createdComments.append(text) }
    func updateComment(id: String, text: String, session: ProgressaSession) async throws {}
    func deleteComment(id: String, session: ProgressaSession) async throws {}
}
