import Foundation
import Testing
@testable import keychain_touchid

@Suite(.serialized) struct AuthCacheTests {
    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let session = SessionScope(sessionID: 100, leaderStartedAt: 1_000, terminal: 7)

    private let item = ItemID(service: "kt-test", account: "sam")
    private let secret = bytes("token")
    private let keychain: TemporaryKeychain
    private let records: KeychainStore

    init() throws {
        keychain = try TemporaryKeychain()
        records = keychain.store(marker: AuthCache.marker)
    }

    private func cache(
        window: Int = 60,
        session: SessionScope? = AuthCacheTests.session,
        after seconds: TimeInterval = 0
    ) -> AuthCache {
        AuthCache(records: records, window: window, session: session, now: { Self.start + seconds })
    }

    @Test func freshRecordCoversTheSecretItWasMadeFor() throws {
        try cache().remember(secret, for: item)

        let record = try #require(cache(after: 30).freshRecord(for: item))

        #expect(AuthCache.covers(record, secret: secret))
        #expect(cache(after: 30).age(of: record) == 30)
    }

    @Test func recordIsValidUpToTheEndOfTheWindow() throws {
        try cache().remember(secret, for: item)

        #expect(cache(after: 60).freshRecord(for: item) != nil)
        #expect(cache(after: 61).freshRecord(for: item) == nil)
    }

    @Test func recordFromTheFutureIsIgnored() throws {
        try cache().remember(secret, for: item)

        #expect(cache(after: -1).freshRecord(for: item) == nil)
    }

    @Test func recordFromAnotherSessionIsIgnored() throws {
        try cache().remember(secret, for: item)

        let otherTab = SessionScope(sessionID: 200, leaderStartedAt: 2_000, terminal: 8)

        #expect(cache(session: otherTab).freshRecord(for: item) == nil)
        #expect(cache(session: nil).freshRecord(for: item) == nil)
    }

    @Test func recordDoesNotCoverADifferentSecret() throws {
        try cache().remember(secret, for: item)

        let record = try #require(cache().freshRecord(for: item))

        #expect(!AuthCache.covers(record, secret: bytes("another token")))
    }

    @Test func malformedRecordIsIgnored() throws {
        try records.add(bytes("{\"createdAt\": \"now\"}"), as: AuthCache.recordID(for: item))

        #expect(cache().freshRecord(for: item) == nil)
    }

    @Test(arguments: [Int.min, Int.max])
    func recordWithAnAbsurdTimestampIsIgnored(createdAt: Int) throws {
        let planted = CacheRecord(
            createdAt: createdAt,
            session: try #require(Self.session),
            secretHash: Data(repeating: 0, count: 32)
        )
        try records.add([UInt8](JSONEncoder().encode(planted)), as: AuthCache.recordID(for: item))

        #expect(cache().freshRecord(for: item) == nil)
    }

    @Test func recordWrittenByAnyoneWithoutTheSecretDoesNotCoverIt() throws {
        let forged = CacheRecord(
            createdAt: Int(Self.start.timeIntervalSince1970),
            session: try #require(Self.session),
            secretHash: Data(repeating: 0, count: 32)
        )
        try records.add([UInt8](JSONEncoder().encode(forged)), as: AuthCache.recordID(for: item))

        let record = try #require(cache().freshRecord(for: item))

        #expect(!AuthCache.covers(record, secret: secret))
    }

    @Test func disabledCacheStoresAndFindsNothing() throws {
        try cache(window: 0).remember(secret, for: item)
        try cache(session: nil).remember(secret, for: item)

        #expect(try records.list(service: nil).isEmpty)

        try cache().remember(secret, for: item)

        #expect(cache(window: 0).freshRecord(for: item) == nil)
    }

    @Test func rememberingAgainReplacesTheRecord() throws {
        try cache().remember(secret, for: item)
        try cache(after: 40).remember(secret, for: item)

        let record = try #require(cache(after: 70).freshRecord(for: item))

        #expect(cache(after: 70).age(of: record) == 30)
        #expect(try records.list(service: nil) == [AuthCache.recordID(for: item)])
    }

    @Test func forgetRemovesTheRecordAndToleratesItsAbsence() throws {
        try cache().remember(secret, for: item)
        try cache().forget(item)
        try cache().forget(item)

        #expect(cache().freshRecord(for: item) == nil)
        #expect(try records.list(service: nil).isEmpty)
    }

    @Test func recordsLiveInTheirOwnNamespace() {
        #expect(AuthCache.recordID(for: item) == ItemID(service: "keychain-touchid-cache:kt-test", account: "sam"))
    }
}
