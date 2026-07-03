import CryptoKit
import Foundation

struct DashboardCache: Codable {
    let summary: HealthSummary
    let workouts: [Workout]
    let savedAt: Date
}

final class DashboardCacheStore {
    private let directory: URL
    private let legacyFileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quantivita", isDirectory: true)
        self.directory = directory
        self.fileManager = fileManager
        legacyFileURL = directory.appendingPathComponent("dashboard-v1.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        legacyFileURL = directory.appendingPathComponent("dashboard-v1.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load(accountId: String) -> DashboardCache? {
        let fileURL = fileURL(accountId: accountId)
        if !fileManager.fileExists(atPath: fileURL.path),
           let legacyData = try? Data(contentsOf: legacyFileURL),
           (try? JSONDecoder().decode(DashboardCache.self, from: legacyData)) != nil {
            do {
                try legacyData.write(to: fileURL, options: [.atomic, .completeFileProtection])
                try fileManager.removeItem(at: legacyFileURL)
            } catch {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
        }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DashboardCache.self, from: data)
    }

    func save(accountId: String, summary: HealthSummary, workouts: [Workout]) {
        let value = DashboardCache(summary: summary, workouts: workouts, savedAt: .now)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL(accountId: accountId), options: [.atomic, .completeFileProtection])
    }

    func clear(accountId: String) {
        try? fileManager.removeItem(at: fileURL(accountId: accountId))
        try? fileManager.removeItem(at: legacyFileURL)
    }

    private func fileURL(accountId: String) -> URL {
        let digest = SHA256.hash(data: Data(accountId.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("dashboard-\(digest).json")
    }
}
