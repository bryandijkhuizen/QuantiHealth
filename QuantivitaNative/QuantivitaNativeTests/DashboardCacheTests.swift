import XCTest
@testable import QuantivitaNative

final class DashboardCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testCachesAreIsolatedByAccount() {
        let store = DashboardCacheStore(directory: directory)
        var firstSummary = HealthSummary()
        firstSummary.steps = 111
        var secondSummary = HealthSummary()
        secondSummary.steps = 222

        store.save(accountId: "account-a", summary: firstSummary, workouts: [])
        store.save(accountId: "account-b", summary: secondSummary, workouts: [])

        XCTAssertEqual(store.load(accountId: "account-a")?.summary.steps, 111)
        XCTAssertEqual(store.load(accountId: "account-b")?.summary.steps, 222)
        XCTAssertNil(store.load(accountId: "account-c"))
    }

    func testLegacyCacheMigratesOnlyToFirstKnownAccount() throws {
        var summary = HealthSummary()
        summary.steps = 333
        let legacy = DashboardCache(summary: summary, workouts: [], savedAt: .now)
        try JSONEncoder().encode(legacy).write(to: directory.appendingPathComponent("dashboard-v1.json"))
        let store = DashboardCacheStore(directory: directory)

        XCTAssertEqual(store.load(accountId: "account-a")?.summary.steps, 333)
        XCTAssertNil(store.load(accountId: "account-b"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("dashboard-v1.json").path))
    }

    func testCorruptLegacyCacheIsNotAssigned() throws {
        let legacyURL = directory.appendingPathComponent("dashboard-v1.json")
        try Data("not-json".utf8).write(to: legacyURL)
        let store = DashboardCacheStore(directory: directory)

        XCTAssertNil(store.load(accountId: "account-a"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    }
}
