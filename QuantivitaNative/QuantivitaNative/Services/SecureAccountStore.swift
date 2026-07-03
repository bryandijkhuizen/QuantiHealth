import CryptoKit
import Foundation
import Security

struct QuantivitaAccount: Codable, Equatable {
    let accountId: String
    let syncToken: String
    let isAppleLinked: Bool
}

protocol AccountDataStore {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func delete() throws
}

protocol LegacyAccountDefaults {
    func string(forKey key: String) -> String?
}

extension UserDefaults: LegacyAccountDefaults {}

final class SecureAccountStore {
    private let dataStore: AccountDataStore
    private let defaults: LegacyAccountDefaults

    init(
        dataStore: AccountDataStore = KeychainAccountDataStore(),
        defaults: LegacyAccountDefaults = UserDefaults.standard
    ) {
        self.dataStore = dataStore
        self.defaults = defaults
    }

    func load() throws -> QuantivitaAccount? {
        if let data = try dataStore.load() {
            return try JSONDecoder().decode(QuantivitaAccount.self, from: data)
        }
        return try migrateFlutterAccount()
    }

    private func migrateFlutterAccount() throws -> QuantivitaAccount? {
        func legacyString(_ key: String) -> String? {
            defaults.string(forKey: key) ?? defaults.string(forKey: "flutter.\(key)")
        }
        guard let accountId = legacyString("quantivita_account_id"), !accountId.isEmpty,
              let syncToken = legacyString("quantivita_sync_token"), !syncToken.isEmpty else { return nil }
        let account = QuantivitaAccount(
            accountId: accountId,
            syncToken: syncToken,
            isAppleLinked: legacyString("apple_user_identifier")?.isEmpty == false
        )
        try save(account)
        return account
    }

    func ensureLocalAccount() throws -> QuantivitaAccount {
        if let account = try load() { return account }
        let token = randomToken()
        let digest = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        let account = QuantivitaAccount(accountId: "qv_local_\(digest.prefix(18))", syncToken: token, isAppleLinked: false)
        try save(account)
        return account
    }

    func linkAppleUser(_ identifier: String) throws -> QuantivitaAccount {
        let digest = SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
        let token = (try load())?.syncToken ?? randomToken()
        let account = QuantivitaAccount(accountId: "qv_\(digest.prefix(24))", syncToken: token, isAppleLinked: true)
        try save(account)
        return account
    }

    /// Removes the stored account identity. Used by account deletion/sign-out.
    func clear() throws {
        try dataStore.delete()
    }

    private func save(_ account: QuantivitaAccount) throws {
        try dataStore.save(JSONEncoder().encode(account))
    }

    private func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

final class KeychainAccountDataStore: AccountDataStore {
    private let service = "com.bryandijkh.quantivita.account"
    private let key = "current-account"

    func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status) }
        return data
    }

    func save(_ data: Data) throws {
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(updateStatus) }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    init(_ status: OSStatus) { self.status = status }
    var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)" }
}
