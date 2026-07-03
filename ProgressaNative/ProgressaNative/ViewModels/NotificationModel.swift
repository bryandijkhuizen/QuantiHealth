import Foundation

@MainActor
final class ProgressaNotificationModel: ObservableObject {
    @Published var notifications: [ProgressaNotification] = []
    @Published var preferences = ProgressaNotificationPreferences()
    @Published var isLoading = false
    @Published var message: String?
    private let service: any ProgressaNotificationServing
    private var session: ProgressaSession?

    init(service: any ProgressaNotificationServing = ProgressaNotificationService()) { self.service = service }

    func configure(_ session: ProgressaSession) async {
        self.session = session
        await refresh()
        do { preferences = try await service.preferences(session: session) } catch {}
    }

    func refresh() async {
        guard let session else { return }
        isLoading = true; defer { isLoading = false }
        do { notifications = try await service.list(session: session) }
        catch { message = "Notifications could not be loaded." }
    }

    func markRead(_ value: ProgressaNotification) async {
        guard value.isUnread, let session else { return }
        if let index = notifications.firstIndex(where: { $0.id == value.id }) { notifications[index].readAt = .now }
        do { try await service.markRead(id: value.id, session: session) }
        catch { await refresh() }
    }

    func respond(_ value: ProgressaNotification, accept: Bool) async {
        guard let session else { return }
        notifications.removeAll { $0.id == value.id }
        do { try await service.respond(notification: value, accept: accept, session: session) }
        catch { message = "The follow request could not be handled."; await refresh() }
    }

    func savePreferences() async {
        guard let session else { return }
        do { try await service.save(preferences, session: session) }
        catch { message = "Notification preferences could not be saved." }
    }
}
