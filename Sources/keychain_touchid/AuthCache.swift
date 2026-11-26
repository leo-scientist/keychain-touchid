import CryptoKit
import Foundation

struct CacheRecord: Codable, Equatable {
    /// Seconds since 1970.
    let createdAt: Int
    let session: SessionScope
    let secretHash: Data
}

/// Remembers a successful authentication for a limited time within one terminal session.
/// See docs/reuse-window.md.
struct AuthCache {
    static let marker = "keychain-touchid cache"
    static let servicePrefix = "keychain-touchid-cache:"

    /// A store that fails instead of asking the user, so a record left by another build is a miss, not a prompt.
    let records: any SecretStore
    /// Seconds; 0 turns the cache off.
    let window: Int
    let session: SessionScope?
    let now: () -> Date

    /// The record for `item` if it is recent enough and belongs to this session. The caller still has to
    /// check that it `covers` the current secret.
    func freshRecord(for item: ItemID) -> CacheRecord? {
        guard window > 0, let session else {
            return nil
        }

        // Whatever is wrong with a record — missing, unreadable, malformed — the answer is to authenticate.
        guard let bytes = try? records.read(Self.recordID(for: item)),
              let record = try? JSONDecoder().decode(CacheRecord.self, from: Data(bytes))
        else {
            return nil
        }

        // The timestamp is whatever was written to the item, so it is compared, never subtracted from.
        let current = Int(now().timeIntervalSince1970)

        guard record.session == session, (current - window...current).contains(record.createdAt) else {
            return nil
        }

        return record
    }

    /// For a record `freshRecord` returned.
    func age(of record: CacheRecord) -> Int {
        Int(now().timeIntervalSince1970) - record.createdAt
    }

    /// Compares in constant time: a record's hash is as good as an authentication to whoever can guess it.
    static func covers(_ record: CacheRecord, secret: [UInt8]) -> Bool {
        SHA256.hash(data: secret) == record.secretHash
    }

    func remember(_ secret: [UInt8], for item: ItemID) throws {
        guard window > 0, let session else {
            return
        }

        let record = CacheRecord(
            createdAt: Int(now().timeIntervalSince1970),
            session: session,
            secretHash: Data(SHA256.hash(data: secret))
        )

        // Replacing instead of updating: an update would keep the trust list of the build that created the record.
        try forget(item)
        try records.add([UInt8](JSONEncoder().encode(record)), as: Self.recordID(for: item))
    }

    func forget(_ item: ItemID) throws {
        do {
            try records.delete(Self.recordID(for: item))
        } catch StoreError.notFound {
            return
        }
    }

    static func recordID(for item: ItemID) -> ItemID {
        ItemID(service: servicePrefix + item.service, account: item.account)
    }
}
