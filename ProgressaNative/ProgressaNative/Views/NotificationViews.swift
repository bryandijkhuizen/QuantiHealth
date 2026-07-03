import SwiftUI

struct ProgressaNotificationsView: View {
    @EnvironmentObject private var app: ProgressaModel
    @StateObject private var model = ProgressaNotificationModel()

    var body: some View {
        List {
            ForEach(model.notifications) { notification in
                HStack(alignment: .top, spacing: 12) {
                    ProgressaAvatarView(
                        path: notification.actorAvatarPath, fallback: notification.actorName,
                        session: app.session
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(notification.actorName).fontWeight(notification.isUnread ? .bold : .semibold)
                            if let handle = notification.actorHandle { Text("@\(handle)").font(.caption).foregroundStyle(.secondary) }
                        }
                        Text(notification.message).foregroundStyle(.secondary)
                        Text(notification.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
                        if notification.isFollowRequest {
                            HStack {
                                Button("Accept") { Task { await model.respond(notification, accept: true) } }.buttonStyle(.borderedProminent)
                                Button("Decline", role: .destructive) { Task { await model.respond(notification, accept: false) } }.buttonStyle(.bordered)
                            }
                        }
                    }
                    if notification.isUnread { Circle().fill(.purple).frame(width: 8, height: 8) }
                }
                .contentShape(Rectangle())
                .onTapGesture { Task { await model.markRead(notification) } }
            }
        }
        .overlay {
            if model.isLoading { ProgressView() }
            else if model.notifications.isEmpty {
                VStack(spacing: 8) { Image(systemName: "bell").font(.largeTitle); Text("No notifications").font(.headline) }
            }
        }
        .navigationTitle("Notifications")
        .refreshable { await model.refresh() }
        .task(id: app.session?.userId) { if let session = app.session { await model.configure(session) } }
        .alert("Progressa", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}

struct ProgressaNotificationSettingsView: View {
    @EnvironmentObject private var app: ProgressaModel
    @StateObject private var model = ProgressaNotificationModel()

    var body: some View {
        Form {
            Toggle("New followers and requests", isOn: $model.preferences.newFollowers)
            Toggle("Likes on my posts", isOn: $model.preferences.likes)
            Toggle("Comments and replies", isOn: $model.preferences.comments)
        }
        .navigationTitle("Notification settings")
        .toolbar { Button("Save") { Task { await model.savePreferences() } } }
        .task(id: app.session?.userId) { if let session = app.session { await model.configure(session) } }
    }
}
