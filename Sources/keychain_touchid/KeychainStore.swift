import Foundation
import Security

enum ItemState: Equatable {
    case absent
    case own
    /// Same service and account, but not created by this tool.
    case foreign
}

enum StoreError: Error, Equatable {
    case notFound
    case duplicateItem
    case accessDenied
    case unexpected(OSStatus)
}

protocol SecretStore {
    func state(of item: ItemID) throws -> ItemState
    func read(_ item: ItemID) throws -> [UInt8]
    func add(_ secret: [UInt8], as item: ItemID) throws
    func update(_ secret: [UInt8], of item: ItemID) throws
    func delete(_ item: ItemID) throws
    func list(service: String?) throws -> [ItemID]
}

/// Generic-password items in the file-based keychain, limited to those carrying `marker`.
/// See docs/keychain.md.
struct KeychainStore: SecretStore {
    static let secretMarker = "keychain-touchid secret"

    let marker: String
    /// `nil` means the user's default keychain; tests pass a throwaway one.
    let keychain: SecKeychain?
    /// When false, a read the Keychain would ask the user about fails with `accessDenied` instead.
    let allowsUserInteraction: Bool

    init(marker: String = secretMarker, keychain: SecKeychain? = nil, allowsUserInteraction: Bool = true) {
        self.marker = marker
        self.keychain = keychain
        self.allowsUserInteraction = allowsUserInteraction
    }

    func state(of item: ItemID) throws -> ItemState {
        if try exists(identity(of: item), ownership) {
            return .own
        }

        return try exists(identity(of: item)) ? .foreign : .absent
    }

    func read(_ item: ItemID) throws -> [UInt8] {
        let query = query([identity(of: item), ownership, searchScope, [
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]])
        var result: CFTypeRef?
        let status = withInteractionPolicy { SecItemCopyMatching(query, &result) }

        guard status == errSecSuccess else {
            throw Self.error(for: status)
        }

        guard let data = result as? Data else {
            throw StoreError.unexpected(errSecInternalError)
        }

        return [UInt8](data)
    }

    func add(_ secret: [UInt8], as item: ItemID) throws {
        let insertScope: [String: Any] = keychain.map { [kSecUseKeychain as String: $0] } ?? [:]
        let attributes = query([identity(of: item), ownership, insertScope, [kSecValueData as String: Data(secret)]])

        try check(SecItemAdd(attributes, nil))
    }

    func update(_ secret: [UInt8], of item: ItemID) throws {
        let changes = [kSecValueData as String: Data(secret)] as CFDictionary

        try check(SecItemUpdate(query([identity(of: item), ownership, searchScope]), changes))
    }

    func delete(_ item: ItemID) throws {
        try check(SecItemDelete(query([identity(of: item), ownership, searchScope])))
    }

    func list(service: String?) throws -> [ItemID] {
        let filter: [String: Any] = service.map { [kSecAttrService as String: $0] } ?? [:]
        let query = query([[kSecClass as String: kSecClassGenericPassword], filter, ownership, searchScope, [
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]])
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query, &result)

        guard status != errSecItemNotFound else {
            return []
        }

        try check(status)
        let rows = result as? [[String: Any]] ?? []

        return rows.compactMap(Self.itemID).sorted { ($0.service, $0.account) < ($1.service, $1.account) }
    }

    private var ownership: [String: Any] {
        [kSecAttrDescription as String: marker]
    }

    private var searchScope: [String: Any] {
        keychain.map { [kSecMatchSearchList as String: [$0]] } ?? [:]
    }

    private func identity(of item: ItemID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecAttrAccount as String: item.account,
        ]
    }

    private func query(_ parts: [[String: Any]]) -> CFDictionary {
        parts.reduce(into: [String: Any]()) { whole, part in whole.merge(part) { _, new in new } } as CFDictionary
    }

    /// Looks at attributes only, which the Keychain allows without consulting the item's trust list.
    private func exists(_ criteria: [String: Any]...) throws -> Bool {
        let query = query(criteria + [searchScope, [
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]])
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query, &result)

        guard status != errSecItemNotFound else {
            return false
        }

        try check(status)

        return true
    }

    /// The switch is process-wide and deprecated without a replacement.
    /// See docs/keychain.md#reading-without-asking-the-user.
    private func withInteractionPolicy<Result>(_ body: () -> Result) -> Result {
        guard !allowsUserInteraction else {
            return body()
        }

        var wasAllowed: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&wasAllowed)
        SecKeychainSetUserInteractionAllowed(false)

        defer {
            SecKeychainSetUserInteractionAllowed(wasAllowed.boolValue)
        }

        return body()
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw Self.error(for: status)
        }
    }

    private static func error(for status: OSStatus) -> StoreError {
        switch status {
        case errSecItemNotFound:
            .notFound
        case errSecDuplicateItem:
            .duplicateItem
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            .accessDenied
        default:
            .unexpected(status)
        }
    }

    private static func itemID(from row: [String: Any]) -> ItemID? {
        guard let service = row[kSecAttrService as String] as? String,
              let account = row[kSecAttrAccount as String] as? String
        else {
            return nil
        }

        return ItemID(service: service, account: account)
    }
}
