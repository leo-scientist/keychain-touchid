import Foundation
import Security
@testable import keychain_touchid

/// A keychain file of its own, so tests never touch the login keychain. It is not added to the search list.
final class TemporaryKeychain {
    let reference: SecKeychain

    init() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychain-touchid-test-\(UUID().uuidString).keychain-db").path
        let password = "test"
        var created: SecKeychain?
        let status = SecKeychainCreate(path, UInt32(password.utf8.count), password, false, nil, &created)

        guard status == errSecSuccess, let created else {
            throw StoreError.unexpected(status)
        }

        reference = created
    }

    deinit {
        SecKeychainDelete(reference)
    }

    func store(marker: String = KeychainStore.secretMarker) -> KeychainStore {
        KeychainStore(marker: marker, keychain: reference, allowsUserInteraction: false)
    }

    /// An item as another program would create it: same service and account, no marker.
    func addForeignItem(_ item: ItemID) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecAttrAccount as String: item.account,
            kSecValueData as String: Data("foreign".utf8),
            kSecUseKeychain as String: reference,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw StoreError.unexpected(status)
        }
    }
}

final class FakeStore: SecretStore {
    var secrets: [ItemID: [UInt8]] = [:]
    var foreignItems: Set<ItemID> = []
    var readError: StoreError?
    private(set) var calls: [String] = []

    func state(of item: ItemID) -> ItemState {
        if secrets[item] != nil {
            return .own
        }

        return foreignItems.contains(item) ? .foreign : .absent
    }

    func read(_ item: ItemID) throws -> [UInt8] {
        calls.append("read")

        if let readError {
            throw readError
        }

        guard let secret = secrets[item] else {
            throw StoreError.notFound
        }

        return secret
    }

    func add(_ secret: [UInt8], as item: ItemID) throws {
        calls.append("add")

        guard state(of: item) == .absent else {
            throw StoreError.duplicateItem
        }

        secrets[item] = secret
    }

    func update(_ secret: [UInt8], of item: ItemID) throws {
        calls.append("update")

        guard secrets[item] != nil else {
            throw StoreError.notFound
        }

        secrets[item] = secret
    }

    func delete(_ item: ItemID) throws {
        calls.append("delete")

        guard secrets.removeValue(forKey: item) != nil else {
            throw StoreError.notFound
        }
    }

    func list(service: String?) -> [ItemID] {
        calls.append("list")

        return secrets.keys
            .filter { service == nil || $0.service == service }
            .sorted { ($0.service, $0.account) < ($1.service, $1.account) }
    }
}

final class FakeAuthenticator: Authenticator {
    var error: AuthenticationError?
    private(set) var reasons: [String] = []

    func authenticate(reason: String) async throws {
        reasons.append(reason)

        if let error {
            throw error
        }
    }
}

func bytes(_ text: String) -> [UInt8] {
    Array(text.utf8)
}
