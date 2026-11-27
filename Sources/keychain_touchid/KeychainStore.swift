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
    case locked
    case unexpected(OSStatus)
}

protocol SecretStore {
    func state(of item: ItemID) throws -> ItemState
    func read(_ item: ItemID) throws -> [UInt8]
    func add(_ secret: [UInt8], as item: ItemID) throws
    func delete(_ item: ItemID) throws
    func list(service: String?) throws -> [ItemID]
    /// Removes whatever item has this service and account, marked or not. Finding nothing is not an error.
    func removeAny(_ item: ItemID) throws
    /// A locked keychain refuses every read, exactly as it refuses a program an item does not trust.
    func isLocked() throws -> Bool
}

extension SecretStore {
    private static var replaceAttempts: Int { 3 }

    /// Writes a secret the only way the tool ever does: by creating the item, after removing whatever has its
    /// name. Only an item's creator can read it silently, so a value must never be written into an item
    /// somebody else created. See docs/keychain.md#writing-a-secret.
    ///
    /// Another process may put an item of its own there between the removal and the creation; that makes the
    /// creation fail, and it is tried again.
    func replace(_ item: ItemID, with secret: [UInt8]) throws {
        // A locked keychain lets an item be removed but not created: the old value would be lost for nothing.
        guard try !isLocked() else {
            throw StoreError.locked
        }

        for attempt in 1...Self.replaceAttempts {
            try removeAny(item)

            do {
                return try add(secret, as: item)
            } catch StoreError.duplicateItem where attempt < Self.replaceAttempts {
                continue
            }
        }
    }
}

/// Generic-password items in the file-based keychain, limited to those carrying `marker`.
/// See docs/keychain.md.
struct KeychainStore: SecretStore {
    static let secretMarker = "keychain-touchid secret"

    private static let loginKeychainPath = "/Library/Keychains/login.keychain-db"

    let marker: String
    /// The one keychain every operation is confined to: the login keychain, or a throwaway one in tests.
    let keychain: SecKeychain
    /// When false, a read the Keychain would ask the user about fails with `accessDenied` instead.
    let allowsUserInteraction: Bool

    init(marker: String = secretMarker, keychain: SecKeychain, allowsUserInteraction: Bool = true) {
        self.marker = marker
        self.keychain = keychain
        self.allowsUserInteraction = allowsUserInteraction
    }

    /// The user's login keychain, at its fixed place in the home directory the user database names.
    ///
    /// Not the default keychain, not the search list and not the environment: a process running as the user
    /// can change each of them, and a secret created in a keychain that process made would be its to read.
    /// See docs/keychain.md#which-keychain.
    static func loginKeychain() throws -> SecKeychain {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else {
            throw StoreError.unexpected(errSecNoSuchKeychain)
        }

        var keychain: SecKeychain?
        let status = SecKeychainOpen(String(cString: home) + loginKeychainPath, &keychain)

        guard status == errSecSuccess, let keychain else {
            throw error(for: status)
        }

        return keychain
    }

    func state(of item: ItemID) throws -> ItemState {
        if try exists(identity(of: item), ownership) {
            return .own
        }

        return try exists(identity(of: item)) ? .foreign : .absent
    }

    func read(_ item: ItemID) throws -> [UInt8] {
        let query = query([
            identity(of: item), ownership, searchScope,
            [
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ],
        ])
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
        let attributes = query([
            identity(of: item), ownership,
            [
                kSecUseKeychain as String: keychain,
                kSecValueData as String: Data(secret),
            ],
        ])

        try check(SecItemAdd(attributes, nil))
    }

    func delete(_ item: ItemID) throws {
        guard try remove([identity(of: item), ownership]) else {
            throw StoreError.notFound
        }
    }

    func removeAny(_ item: ItemID) throws {
        _ = try remove([identity(of: item)])
    }

    func isLocked() throws -> Bool {
        var status = SecKeychainStatus()
        try check(SecKeychainGetStatus(keychain, &status))

        return status & kSecUnlockStateStatus == 0
    }

    func list(service: String?) throws -> [ItemID] {
        let filter: [String: Any] = service.map { [kSecAttrService as String: $0] } ?? [:]
        let query = query([
            [kSecClass as String: kSecClassGenericPassword], filter, ownership, searchScope,
            [
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ],
        ])
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
        [kSecMatchSearchList as String: [keychain]]
    }

    /// Removes every matching item and tells whether there was any.
    ///
    /// Goes through item references rather than `SecItemDelete`, which refuses an item another program
    /// created (`errSecInvalidOwnerEdit`), including one stored by an earlier build of this tool.
    /// See docs/keychain.md#what-another-program-can-do.
    private func remove(_ criteria: [[String: Any]]) throws -> Bool {
        let query = query(
            criteria + [
                searchScope,
                [
                    kSecReturnRef as String: true,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                ],
            ])
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query, &result)

        guard status != errSecItemNotFound else {
            return false
        }

        try check(status)
        let references = result as? [SecKeychainItem] ?? []

        for reference in references {
            try check(SecKeychainItemDelete(reference))
        }

        return !references.isEmpty
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

    /// Looks at attributes only, which the Keychain allows to any program.
    private func exists(_ criteria: [String: Any]...) throws -> Bool {
        let query = query(
            criteria + [
                searchScope,
                [
                    kSecReturnAttributes as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                ],
            ])
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
