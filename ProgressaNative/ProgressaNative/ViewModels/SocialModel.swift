import Foundation

@MainActor
final class SocialModel: ObservableObject {
    @Published var mode: FeedMode = .following
    @Published var posts: [SocialPost] = []
    @Published var syncState: FeedSyncState = .idle
    @Published var people: [SocialUser] = []
    @Published var followStatuses: [String: String] = [:]
    @Published var profilePosts: [String: [SocialPost]] = [:]
    @Published var likedPostIDs: Set<String> = []
    @Published var commentsByPost: [String: [SocialComment]] = [:]
    @Published var isLoading = false
    @Published var message: String?

    private let service: SocialServing
    private let cache: SocialCache
    private var session: ProgressaSession?

    init(service: SocialServing = SocialClient(), cache: SocialCache = SocialCache()) {
        self.service = service
        self.cache = cache
    }

    func configure(session: ProgressaSession) async {
        guard self.session?.userId != session.userId else { return }
        self.session = session
        posts = []
        people = []
        followStatuses = [:]
        profilePosts = [:]
        likedPostIDs = []
        commentsByPost = [:]
        loadCache()
        await refresh()
    }

    func select(_ mode: FeedMode) async {
        guard self.mode != mode else { return }
        self.mode = mode
        loadCache()
        await refresh()
    }

    func refresh() async {
        guard let session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await service.fetchFeed(mode, session: session).sorted { $0.createdAt > $1.createdAt }
            posts = fresh
            let now = Date.now
            try cache.save(fresh, userId: session.userId, mode: mode, at: now)
            syncState = .fresh(now)
        } catch {
            loadCache()
            syncState = .cached(cache.load(userId: session.userId, mode: mode)?.savedAt)
            message = posts.isEmpty ? "Feed could not be loaded." : "Offline: cached posts are still shown."
        }
    }

    @discardableResult
    func createPost(text: String, visibility: String) async -> Bool {
        guard let session else { return false }
        do {
            try await service.createPost(text: text, visibility: visibility, session: session)
            mode = .following
            await refresh()
            return true
        } catch { message = "Creating a post requires a connection. \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func updatePost(_ post: SocialPost, text: String) async -> Bool {
        guard let session, post.authorId == session.userId else { return false }
        do {
            try await service.updatePost(id: post.id, text: text, session: session)
            if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index].text = text }
            try cache.save(posts, userId: session.userId, mode: mode)
            return true
        } catch { message = "Editing this post requires a connection. \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func deletePost(_ post: SocialPost) async -> Bool {
        guard let session, post.authorId == session.userId else { return false }
        do {
            try await service.deletePost(id: post.id, session: session)
            posts.removeAll { $0.id == post.id }
            try cache.save(posts, userId: session.userId, mode: mode)
            return true
        } catch { message = "Deleting this post requires a connection. \(error.localizedDescription)"; return false }
    }

    func search(_ query: String) async {
        guard let session else { return }
        do {
            people = try await service.searchUsers(query, session: session)
            for user in people.prefix(20) where followStatuses[user.id] == nil {
                followStatuses[user.id] = try? await service.followStatus(user.id, session: session)
            }
        } catch { message = error.localizedDescription }
    }

    func toggleFollow(_ user: SocialUser) async {
        guard let session else { return }
        do {
            if followStatuses[user.id] == "accepted" || followStatuses[user.id] == "requested" {
                try await service.unfollow(user.id, session: session)
                followStatuses[user.id] = "none"
            } else {
                followStatuses[user.id] = try await service.follow(user.id, session: session)
            }
        } catch { message = error.localizedDescription }
    }

    func loadProfile(_ user: SocialUser) async {
        guard let session else { return }
        if followStatuses[user.id] == nil { followStatuses[user.id] = try? await service.followStatus(user.id, session: session) }
        do { profilePosts[user.id] = try await service.profilePosts(user.id, session: session) }
        catch { profilePosts[user.id] = [] }
    }

    func followers(of userId: String) async -> [SocialUser] {
        guard let session else { return [] }
        do { return try await service.followers(userId, session: session) }
        catch { message = "Followers could not be loaded."; return [] }
    }

    func following(of userId: String) async -> [SocialUser] {
        guard let session else { return [] }
        do { return try await service.following(userId, session: session) }
        catch { message = "Following could not be loaded."; return [] }
    }

    func likers(of post: SocialPost) async -> [SocialUser] {
        guard let session else { return [] }
        do { return try await service.postLikers(post.id, session: session) }
        catch { message = "Likes could not be loaded."; return [] }
    }

    func loadLikeStatus(_ post: SocialPost) async {
        guard let session else { return }
        if (try? await service.isPostLiked(post.id, session: session)) == true { likedPostIDs.insert(post.id) }
        else { likedPostIDs.remove(post.id) }
    }

    func toggleLike(_ post: SocialPost) async {
        guard let session else { return }
        let shouldLike = !likedPostIDs.contains(post.id)
        if shouldLike { likedPostIDs.insert(post.id) } else { likedPostIDs.remove(post.id) }
        adjustPost(id: post.id, likes: shouldLike ? 1 : -1, comments: 0)
        do { try await service.setPostLiked(shouldLike, postId: post.id, session: session) }
        catch {
            if shouldLike { likedPostIDs.remove(post.id) } else { likedPostIDs.insert(post.id) }
            adjustPost(id: post.id, likes: shouldLike ? -1 : 1, comments: 0)
            message = "The like could not be saved."
        }
    }

    func loadComments(postId: String) async {
        guard let session else { return }
        do { commentsByPost[postId] = try await service.comments(postId, session: session) }
        catch { message = "Comments could not be loaded." }
    }

    func createComment(postId: String, text: String, parentId: String? = nil) async -> Bool {
        guard let session else { return false }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        do {
            try await service.createComment(postId: postId, text: clean, parentId: parentId, session: session)
            adjustPost(id: postId, likes: 0, comments: 1)
            await loadComments(postId: postId)
            return true
        } catch { message = "The comment could not be posted."; return false }
    }

    func toggleCommentLike(_ comment: SocialComment) async {
        guard let session else { return }
        let shouldLike = !comment.isLiked
        adjustComment(id: comment.id, postId: comment.postId, liked: shouldLike, delta: shouldLike ? 1 : -1)
        do { try await service.setCommentLiked(shouldLike, commentId: comment.id, session: session) }
        catch {
            adjustComment(id: comment.id, postId: comment.postId, liked: !shouldLike, delta: shouldLike ? -1 : 1)
            message = "The like could not be saved."
        }
    }

    func updateComment(_ comment: SocialComment, text: String) async -> Bool {
        guard let session, comment.userId == session.userId else { return false }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        do { try await service.updateComment(id: comment.id, text: clean, session: session); await loadComments(postId: comment.postId); return true }
        catch { message = "The comment could not be updated."; return false }
    }

    func deleteComment(_ comment: SocialComment, post: SocialPost) async {
        guard let session, comment.userId == session.userId || post.authorId == session.userId else { return }
        do {
            try await service.deleteComment(id: comment.id, session: session)
            commentsByPost[post.id]?.removeAll { $0.id == comment.id || $0.parentId == comment.id }
            adjustPost(id: post.id, likes: 0, comments: -1)
        } catch { message = "The comment could not be deleted." }
    }

    func isMine(_ post: SocialPost) -> Bool { post.authorId == session?.userId }
    func isCurrentUser(_ user: SocialUser) -> Bool { user.id == session?.userId }
    var activeSession: ProgressaSession? { session }

    private func adjustComment(id: String, postId: String, liked: Bool, delta: Int) {
        guard let index = commentsByPost[postId]?.firstIndex(where: { $0.id == id }) else { return }
        commentsByPost[postId]?[index].isLiked = liked
        commentsByPost[postId]?[index].likeCount = max(0, (commentsByPost[postId]?[index].likeCount ?? 0) + delta)
    }

    private func adjustPost(id: String, likes: Int, comments: Int) {
        if let index = posts.firstIndex(where: { $0.id == id }) {
            posts[index].likeCount = max(0, posts[index].likeCount + likes)
            posts[index].commentsCount = max(0, posts[index].commentsCount + comments)
        }
        for user in profilePosts.keys {
            if let index = profilePosts[user]?.firstIndex(where: { $0.id == id }) {
                profilePosts[user]?[index].likeCount = max(0, (profilePosts[user]?[index].likeCount ?? 0) + likes)
                profilePosts[user]?[index].commentsCount = max(0, (profilePosts[user]?[index].commentsCount ?? 0) + comments)
            }
        }
    }

    private func loadCache() {
        guard let session, let cached = cache.load(userId: session.userId, mode: mode) else {
            posts = []
            syncState = .cached(nil)
            return
        }
        posts = cached.posts
        syncState = .cached(cached.savedAt)
    }
}
