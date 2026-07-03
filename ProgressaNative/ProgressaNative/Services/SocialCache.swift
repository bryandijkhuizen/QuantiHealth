import Foundation

final class SocialCache {
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProgressaNative/Social", isDirectory: true)
    }

    func load(userId: String, mode: FeedMode) -> CachedFeed? {
        guard let data = try? Data(contentsOf: fileURL(userId: userId, mode: mode)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedFeed.self, from: data)
    }

    func save(_ posts: [SocialPost], userId: String, mode: FeedMode, at date: Date = .now) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(CachedFeed(posts: posts, savedAt: date))
            .write(to: fileURL(userId: userId, mode: mode), options: .atomic)
    }

    private func fileURL(userId: String, mode: FeedMode) -> URL {
        let safe = userId.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        return directory.appendingPathComponent("feed-\(safe)-\(mode.rawValue.lowercased()).json")
    }
}
