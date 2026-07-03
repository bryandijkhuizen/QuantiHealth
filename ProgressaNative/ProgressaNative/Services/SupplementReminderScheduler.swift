import Foundation
import UserNotifications

protocol SupplementReminderScheduling {
    func apply(_ preferences: SupplementPreferences, supplementName: String, requestPermission: Bool) async throws
    func cancel(supplementId: String)
}

enum ReminderError: LocalizedError {
    case permissionDenied
    var errorDescription: String? { "Notifications are disabled for Progressa in iOS Settings." }
}

final class SupplementReminderScheduler: SupplementReminderScheduling {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) { self.center = center }

    func apply(_ preferences: SupplementPreferences, supplementName: String, requestPermission: Bool) async throws {
        cancel(supplementId: preferences.supplementId)
        guard preferences.reminderEnabled else { return }
        if requestPermission {
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { throw ReminderError.permissionDenied }
        } else {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        }
        for (suffix, weekday) in scheduleDays(preferences) {
            var date = DateComponents(); date.hour = preferences.hour; date.minute = preferences.minute; date.weekday = weekday
            let content = UNMutableNotificationContent(); content.title = "Supplement reminder"; content.body = "Take \(supplementName)"; content.sound = .default
            content.userInfo = ["kind": "supplement_reminder", "supplementId": preferences.supplementId]
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            try await center.add(UNNotificationRequest(identifier: identifier(preferences.supplementId, suffix), content: content, trigger: trigger))
        }
    }

    func cancel(supplementId: String) {
        center.removePendingNotificationRequests(withIdentifiers: (0...7).map { identifier(supplementId, String($0)) } + [identifier(supplementId, "daily")])
    }

    private func scheduleDays(_ value: SupplementPreferences) -> [(String, Int?)] {
        switch value.frequency {
        case .daily: return [("daily", nil)]
        case .weekly: return [(String(value.weekday), calendarWeekday(value.weekday))]
        case .custom:
            return (1...7).compactMap { day in value.weekdaysMask & (1 << (day - 1)) != 0 ? (String(day), calendarWeekday(day)) : nil }
        }
    }
    private func calendarWeekday(_ mondayBased: Int) -> Int { mondayBased % 7 + 1 }
    private func identifier(_ id: String, _ suffix: String) -> String { "progressa.supplement.\(id).\(suffix)" }
}
