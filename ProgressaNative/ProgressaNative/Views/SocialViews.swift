import SwiftUI
import MapKit

struct ProgressaFeedView: View {
    @EnvironmentObject private var app: ProgressaModel
    @StateObject private var model = SocialModel()
    @State private var showingComposer = false
    @State private var showingSearch = false

    var body: some View {
        List {
            Picker("Feed", selection: Binding(
                get: { model.mode }, set: { value in Task { await model.select(value) } }
            )) {
                ForEach(FeedMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)

            if case let .cached(savedAt) = model.syncState {
                Label(savedAt.map { "Offline copy from \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Offline copy", systemImage: "icloud.slash")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            ForEach(model.posts) { post in
                SocialPostRow(post: post, model: model)
            }
        }
        .overlay { if model.posts.isEmpty && !model.isLoading { SocialEmptyState() } }
        .navigationTitle("Feed")
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingSearch = true } label: { Label("Find people", systemImage: "person.badge.plus") }
                Button { showingComposer = true } label: { Label("New post", systemImage: "square.and.pencil") }
            }
        }
        .sheet(isPresented: $showingComposer) { SocialPostEditor(model: model) }
        .sheet(isPresented: $showingSearch) { SocialSearchView(model: model) }
        .alert("Progressa", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .task(id: app.session?.userId) { if let session = app.session { await model.configure(session: session) } }
    }
}

private struct SocialPostRow: View {
    let post: SocialPost
    @ObservedObject var model: SocialModel
    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SocialPostContent(post: post, model: model, onOpen: { showingDetail = true })
            HStack {
                Button { Task { await model.toggleLike(post) } } label: {
                    Label("\(post.likeCount)", systemImage: model.likedPostIDs.contains(post.id) ? "heart.fill" : "heart")
                }.tint(model.likedPostIDs.contains(post.id) ? .red : .secondary)
                Button { showingDetail = true } label: { Label("\(post.commentsCount)", systemImage: "bubble.left") }
                    .tint(.secondary)
            }.font(.caption).buttonStyle(.borderless)
        }.padding(.vertical, 4)
        .task { await model.loadLikeStatus(post) }
        .sheet(isPresented: $showingDetail) { SocialPostDetailView(post: post, model: model) }
    }
}

/// Shared author header + text + workout card, used by both the feed row and the
/// Twitter-style detail view. When `onOpen` is set the body is tappable to open detail.
private struct SocialPostContent: View {
    let post: SocialPost
    @ObservedObject var model: SocialModel
    var onOpen: (() -> Void)? = nil
    @State private var editing = false
    @State private var deleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NavigationLink { SocialProfileView(user: author, model: model) } label: {
                    HStack {
                        ProgressaAvatarView(path: post.avatarPath, fallback: post.authorName, session: model.activeSession)
                        VStack(alignment: .leading) {
                            Text(post.authorName).font(.headline)
                            if let handle = post.authorHandle { Text("@\(handle)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Spacer()
                Text(post.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                if model.isMine(post) {
                    Menu {
                        Button("Edit") { editing = true }
                        Button("Delete", role: .destructive) { deleting = true }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
            postBody
        }
        .sheet(isPresented: $editing) { SocialPostEditor(model: model, post: post) }
        .confirmationDialog("Delete this post?", isPresented: $deleting) {
            Button("Delete post", role: .destructive) { Task { _ = await model.deletePost(post) } }
        }
    }

    @ViewBuilder private var postBody: some View {
        if let onOpen {
            Button(action: onOpen) { bodyContent }.buttonStyle(.plain)
        } else {
            bodyContent
        }
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text = post.text { Text(text).frame(maxWidth: .infinity, alignment: .leading) }
            if let share = post.workoutShare { WorkoutShareCard(snapshot: share) }
            else if let title = post.workoutTitle { WorkoutTitleCard(title: title) }
        }.contentShape(Rectangle())
    }

    private var author: SocialUser {
        SocialUser(userId: post.authorId, fullName: post.authorName, handle: post.authorHandle, avatarPath: post.avatarPath, profileVisibility: "public")
    }
}

private struct WorkoutShareCard: View {
    let snapshot: WorkoutShareSnapshot

    /// A workout with logged exercises is a strength ("fitness") workout; anything
    /// without exercise groups is a non-fitness activity rendered as a health card.
    private var isFitness: Bool { !snapshot.groups.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: isFitness ? "dumbbell.fill" : activityIcon)
                    .font(.title2).foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(isFitness ? Color.accentColor.gradient : Color.orange.gradient, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.workoutTitle).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if isFitness {
                HStack(spacing: 8) {
                    metric("\(snapshot.groups.count) exercises", icon: "figure.strengthtraining.traditional")
                    metric("\(snapshot.totalSets) sets", icon: "list.number")
                }
                ForEach(snapshot.groups.prefix(3)) { group in
                    HStack {
                        Text(group.exerciseName).lineLimit(1)
                        Spacer()
                        Text(group.sets.isEmpty ? "No sets" : "\(group.sets.count) sets")
                            .foregroundStyle(.secondary)
                    }.font(.subheadline)
                }
            } else {
                let chips = activityMetrics
                if chips.isEmpty {
                    Text("Activity logged").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) { ForEach(chips, id: \.icon) { metric($0.value, icon: $0.icon) } }
                }
                if let heartRate = snapshot.averageHeartRate, heartRate > 0 {
                    Label("Avg \(Int(heartRate)) bpm" + (snapshot.maxHeartRate.map { " · Max \(Int($0))" } ?? ""), systemImage: "heart.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.red)
                }
            }
            if !snapshot.routePoints.isEmpty {
                RouteMapView(
                    coordinates: snapshot.routePoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
                    height: 140
                )
            }
            if let location = snapshot.location {
                Label(location, systemImage: "location.fill").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.quaternary) }
    }

    private var subtitle: String {
        isFitness ? "Strength workout" : (snapshot.activityType ?? "Activity")
    }

    private var activityIcon: String {
        let value = snapshot.activityType?.lowercased() ?? ""
        if value.contains("cycl") || value.contains("bike") { return "bicycle" }
        if value.contains("swim") { return "figure.pool.swim" }
        if value.contains("walk") { return "figure.walk" }
        if value.contains("hik") { return "figure.hiking" }
        if value.contains("yoga") { return "figure.yoga" }
        if value.contains("run") { return "figure.run" }
        return "figure.mixed.cardio"
    }

    private var activityMetrics: [(icon: String, value: String)] {
        var chips: [(icon: String, value: String)] = []
        if let duration = snapshot.durationSeconds, duration > 0 { chips.append(("clock", "\(Int(duration / 60)) min")) }
        if let distanceMeters = snapshot.distanceMeters, distanceMeters > 0 {
            chips.append(("point.topleft.down.to.point.bottomright.curvepath", distance(distanceMeters)))
        }
        if let calories = snapshot.calories, calories > 0 { chips.append(("flame.fill", "\(Int(calories)) kcal")) }
        return chips
    }

    private func distance(_ meters: Double) -> String {
        meters >= 1_000 ? "\((meters / 1_000).formatted(.number.precision(.fractionLength(1)))) km" : "\(Int(meters)) m"
    }
    private func metric(_ value: String, icon: String) -> some View {
        Label(value, systemImage: icon).font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule()).lineLimit(1).minimumScaleFactor(0.75)
    }
}

/// Fallback card for a workout post whose snapshot could not be loaded.
private struct WorkoutTitleCard: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.mixed.cardio").font(.title2).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(2)
                Text("Activity").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.quaternary) }
    }
}

private struct SocialPostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SocialModel
    let post: SocialPost?
    @State private var text: String
    @State private var visibility: String
    @State private var saving = false

    init(model: SocialModel, post: SocialPost? = nil) {
        self.model = model; self.post = post
        _text = State(initialValue: post?.text ?? "")
        _visibility = State(initialValue: post?.visibility ?? "public")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $text).frame(minHeight: 140)
                if post == nil {
                    Picker("Visibility", selection: $visibility) {
                        Text("Public").tag("public"); Text("Friends").tag("friends"); Text("Private").tag("private")
                    }
                }
            }
            .navigationTitle(post == nil ? "New post" : "Edit post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            saving = true
                            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            let success = if let post { await model.updatePost(post, text: clean) }
                                else { await model.createPost(text: clean, visibility: visibility) }
                            saving = false
                            if success { dismiss() }
                        }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
        }
    }
}

private struct SocialSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SocialModel
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(model.people) { user in
                NavigationLink { SocialProfileView(user: user, model: model) } label: {
                    HStack {
                        ProgressaAvatarView(path: user.avatarPath, fallback: user.fullName, session: model.activeSession)
                        VStack(alignment: .leading) { Text(user.fullName); if let handle = user.handle { Text("@\(handle)").font(.caption).foregroundStyle(.secondary) } }
                        Spacer()
                        followLabel(user)
                    }
                }
                .swipeActions {
                    Button { Task { await model.toggleFollow(user) } } label: { followLabel(user) }.tint(.purple)
                }
            }
            .navigationTitle("Find people")
            .searchable(text: $query, prompt: "Name or handle")
            .onSubmit(of: .search) { Task { await model.search(query) } }
            .toolbar { Button("Done") { dismiss() } }
            .task { await model.search("") }
        }
    }

    private func followLabel(_ user: SocialUser) -> some View {
        Text(model.followStatuses[user.id] == "accepted" ? "Following" : model.followStatuses[user.id] == "requested" ? "Requested" : "Follow")
            .font(.caption).foregroundStyle(.secondary)
    }
}

private struct SocialProfileView: View {
    let user: SocialUser
    @ObservedObject var model: SocialModel

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ProgressaAvatarView(path: user.avatarPath, fallback: user.fullName, session: model.activeSession, size: 72)
                    VStack(alignment: .leading) {
                        Text(user.fullName).font(.title2.bold())
                        if let handle = user.handle { Text("@\(handle)").foregroundStyle(.secondary) }
                        if let country = user.country { Text(country) }
                    }
                }
                if !model.isCurrentUser(user) {
                    Button(actionTitle) { Task { await model.toggleFollow(user) } }
                }
            }
            Section {
                NavigationLink {
                    SocialUserListView(title: "Followers", model: model) { await model.followers(of: user.id) }
                } label: { Label("Followers", systemImage: "person.2") }
                NavigationLink {
                    SocialUserListView(title: "Following", model: model) { await model.following(of: user.id) }
                } label: { Label("Following", systemImage: "person.2.fill") }
            }
            Section("Posts") {
                ForEach(model.profilePosts[user.id] ?? []) { post in
                    SocialPostRow(post: post, model: model)
                }
            }
        }.navigationTitle("Profile").task { await model.loadProfile(user) }
    }

    private var actionTitle: String {
        model.followStatuses[user.id] == "accepted" ? "Unfollow" : model.followStatuses[user.id] == "requested" ? "Cancel request" : "Follow"
    }
}

/// Reusable list of users (followers, following, likers) that links to each profile.
private struct SocialUserListView: View {
    let title: String
    @ObservedObject var model: SocialModel
    let load: () async -> [SocialUser]
    @State private var users: [SocialUser] = []
    @State private var loaded = false

    var body: some View {
        List(users) { user in
            NavigationLink { SocialProfileView(user: user, model: model) } label: {
                HStack {
                    ProgressaAvatarView(path: user.avatarPath, fallback: user.fullName, session: model.activeSession)
                    VStack(alignment: .leading) {
                        Text(user.fullName)
                        if let handle = user.handle { Text("@\(handle)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .overlay {
            if users.isEmpty && loaded {
                Text("Nobody yet").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .task { users = await load(); loaded = true }
    }
}

/// Twitter-style detail: the post on top, comments below, with a reply composer.
private struct SocialPostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let post: SocialPost
    @ObservedObject var model: SocialModel
    @State private var draft = ""
    @State private var editingComment: SocialComment?
    @State private var editText = ""
    @State private var replyTarget: SocialComment?
    @State private var showingLikers = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SocialPostContent(post: post, model: model)
                    HStack(spacing: 18) {
                        Button { Task { await model.toggleLike(post) } } label: {
                            Image(systemName: model.likedPostIDs.contains(post.id) ? "heart.fill" : "heart")
                        }.tint(model.likedPostIDs.contains(post.id) ? .red : .secondary)
                        Button { showingLikers = true } label: { Text("\(post.likeCount) likes") }
                            .tint(.secondary).disabled(post.likeCount == 0)
                        Label("\(post.commentsCount)", systemImage: "bubble.left").foregroundStyle(.secondary)
                        Spacer()
                    }.font(.caption).buttonStyle(.borderless)
                }
                Section("Comments") {
                    let comments = model.commentsByPost[post.id] ?? []
                    if comments.isEmpty {
                        Text("No comments yet. Start the conversation.").foregroundStyle(.secondary).font(.subheadline)
                    }
                    ForEach(comments) { comment in commentRow(comment) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if let replyTarget {
                        HStack {
                            Text("Replying to \(replyTarget.authorHandle.map { "@\($0)" } ?? replyTarget.authorName)")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { self.replyTarget = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        }
                    }
                    HStack {
                        TextField(replyTarget == nil ? "Write a comment" : "Write a reply", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder)
                        Button("Post") {
                            Task {
                                if await model.createComment(postId: post.id, text: draft, parentId: replyTarget?.id) {
                                    draft = ""; replyTarget = nil
                                }
                            }
                        }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.padding().background(.bar)
            }
            .navigationTitle("Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $showingLikers) {
                NavigationStack {
                    SocialUserListView(title: "Liked by", model: model) { await model.likers(of: post) }
                        .toolbar { Button("Done") { showingLikers = false } }
                }
            }
            .task { await model.loadLikeStatus(post); await model.loadComments(postId: post.id) }
            .sheet(item: $editingComment) { comment in
                NavigationStack {
                    Form { TextEditor(text: $editText).frame(minHeight: 120) }
                        .navigationTitle("Edit comment")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingComment = nil } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") { Task { if await model.updateComment(comment, text: editText) { editingComment = nil } } }
                            }
                        }
                }
            }
        }
    }

    private func commentRow(_ comment: SocialComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressaAvatarView(path: comment.avatarPath, fallback: comment.authorName, session: model.activeSession, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(comment.authorName).font(.subheadline.bold())
                    if let handle = comment.authorHandle { Text("@\(handle)").font(.caption).foregroundStyle(.secondary) }
                }
                Text(comment.text)
                Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Button { Task { await model.toggleCommentLike(comment) } } label: {
                        Label("\(comment.likeCount)", systemImage: comment.isLiked ? "heart.fill" : "heart")
                    }.tint(comment.isLiked ? .red : .secondary)
                    Button { replyTarget = comment } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                        .tint(.secondary)
                }.font(.caption2).buttonStyle(.borderless).padding(.top, 1)
            }
            Spacer()
            if comment.userId == model.activeSession?.userId || post.authorId == model.activeSession?.userId {
                Menu {
                    if comment.userId == model.activeSession?.userId {
                        Button("Edit") { editText = comment.text; editingComment = comment }
                    }
                    Button("Delete", role: .destructive) { Task { await model.deleteComment(comment, post: post) } }
                } label: { Image(systemName: "ellipsis") }
            }
        }.padding(.leading, comment.parentId == nil ? 0 : 28)
    }
}

private struct SocialEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right").font(.largeTitle)
            Text("No posts yet").font(.headline)
            Text("Follow people or write the first post.").foregroundStyle(.secondary)
        }
    }
}
