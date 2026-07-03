import XCTest
@testable import QuantivitaNative

final class AccountMigrationTests: XCTestCase {
    func testMigratesFlutterPrefixedAccountExactly() throws {
        let dataStore = MemoryAccountDataStore()
        let defaults = DictionaryDefaults(values: [
            "flutter.quantivita_account_id": "qv_existing",
            "flutter.quantivita_sync_token": "existing-token",
            "flutter.apple_user_identifier": "apple-user",
        ])

        let account = try SecureAccountStore(dataStore: dataStore, defaults: defaults).load()

        XCTAssertEqual(account, QuantivitaAccount(accountId: "qv_existing", syncToken: "existing-token", isAppleLinked: true))
        XCTAssertNotNil(dataStore.data)
    }

    func testMigratesUnprefixedOfflineAccount() throws {
        let store = SecureAccountStore(
            dataStore: MemoryAccountDataStore(),
            defaults: DictionaryDefaults(values: [
                "quantivita_account_id": "qv_local_existing",
                "quantivita_sync_token": "offline-token",
            ])
        )

        XCTAssertEqual(
            try store.load(),
            QuantivitaAccount(accountId: "qv_local_existing", syncToken: "offline-token", isAppleLinked: false)
        )
    }

    func testExistingKeychainAccountWinsOverLegacyDefaults() throws {
        let existing = QuantivitaAccount(accountId: "keychain", syncToken: "keychain-token", isAppleLinked: false)
        let dataStore = MemoryAccountDataStore(data: try JSONEncoder().encode(existing))
        let defaults = DictionaryDefaults(values: [
            "flutter.quantivita_account_id": "legacy",
            "flutter.quantivita_sync_token": "legacy-token",
        ])

        XCTAssertEqual(try SecureAccountStore(dataStore: dataStore, defaults: defaults).load(), existing)
        XCTAssertEqual(dataStore.saveCount, 0)
    }

    func testIncompleteLegacyAccountDoesNotMigrate() throws {
        for values in [
            ["flutter.quantivita_account_id": "id-only"],
            ["flutter.quantivita_sync_token": "token-only"],
            ["flutter.quantivita_account_id": "", "flutter.quantivita_sync_token": "token"],
        ] {
            let dataStore = MemoryAccountDataStore()
            let store = SecureAccountStore(dataStore: dataStore, defaults: DictionaryDefaults(values: values))
            XCTAssertNil(try store.load())
            XCTAssertNil(dataStore.data)
        }
    }

    func testMigrationFailureLeavesLegacyDefaultsUntouched() {
        let values = [
            "flutter.quantivita_account_id": "legacy",
            "flutter.quantivita_sync_token": "legacy-token",
        ]
        let defaults = DictionaryDefaults(values: values)
        let dataStore = MemoryAccountDataStore(saveError: TestError.writeFailed)

        XCTAssertThrowsError(try SecureAccountStore(dataStore: dataStore, defaults: defaults).load())
        XCTAssertEqual(defaults.values, values)
    }

    func testMigrationIsIdempotentAfterFirstLaunch() throws {
        let dataStore = MemoryAccountDataStore()
        let defaults = DictionaryDefaults(values: [
            "flutter.quantivita_account_id": "legacy",
            "flutter.quantivita_sync_token": "legacy-token",
        ])
        let store = SecureAccountStore(dataStore: dataStore, defaults: defaults)

        let first = try store.load()
        defaults.values["flutter.quantivita_account_id"] = "changed-after-migration"
        let second = try store.load()

        XCTAssertEqual(first, second)
        XCTAssertEqual(dataStore.saveCount, 1)
    }
}

private enum TestError: Error { case writeFailed }

private final class MemoryAccountDataStore: AccountDataStore {
    var data: Data?
    var saveCount = 0
    var saveError: Error?

    init(data: Data? = nil, saveError: Error? = nil) {
        self.data = data
        self.saveError = saveError
    }

    func load() throws -> Data? { data }

    func save(_ data: Data) throws {
        if let saveError { throw saveError }
        self.data = data
        saveCount += 1
    }

    func delete() throws { data = nil }
}

private final class DictionaryDefaults: LegacyAccountDefaults {
    var values: [String: String]
    init(values: [String: String]) { self.values = values }
    func string(forKey key: String) -> String? { values[key] }
}
