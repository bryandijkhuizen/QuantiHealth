import Foundation

final class NutritionStore {
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProgressaNative/Nutrition", isDirectory: true)
    }

    func loadFood(userId: String) -> FoodSnapshot {
        load(FoodSnapshot.self, name: "food", userId: userId) ?? FoodSnapshot(entries: [], goal: .default)
    }
    func saveFood(_ value: FoodSnapshot, userId: String) throws { try save(value, name: "food", userId: userId) }
    func loadSupplements(userId: String) -> SupplementSnapshot? { load(SupplementSnapshot.self, name: "supplements", userId: userId) }
    func saveSupplements(_ value: SupplementSnapshot, userId: String) throws { try save(value, name: "supplements", userId: userId) }

    private func load<T: Decodable>(_ type: T.Type, name: String, userId: String) -> T? {
        guard let data = try? Data(contentsOf: url(name: name, userId: userId)) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
    private func save<T: Encodable>(_ value: T, name: String, userId: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url(name: name, userId: userId), options: .atomic)
    }
    private func url(name: String, userId: String) -> URL {
        let safe = userId.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        return directory.appendingPathComponent("\(name)-\(safe).json")
    }
}
