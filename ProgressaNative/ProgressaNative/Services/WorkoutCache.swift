import Foundation

final class WorkoutCache {
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProgressaNative", isDirectory: true)
    }

    func load(userId: String) -> CachedWorkouts? {
        guard let data = try? Data(contentsOf: fileURL(userId: userId)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedWorkouts.self, from: data)
    }

    func save(_ workouts: [ProgressaWorkout], userId: String, at date: Date = .now) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var protectedDirectory = directory
        try? protectedDirectory.setResourceValues(resourceValues)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(CachedWorkouts(workouts: workouts, savedAt: date))
        try data.write(to: fileURL(userId: userId), options: [.atomic, .completeFileProtection])
    }

    func clear(userId: String) {
        try? FileManager.default.removeItem(at: fileURL(userId: userId))
    }

    private func fileURL(userId: String) -> URL {
        let safeId = userId.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        return directory.appendingPathComponent("workouts-\(safeId).json")
    }
}
