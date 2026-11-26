import Testing
@testable import keychain_touchid

@Suite(.serialized) struct KeychainStoreTests {
    private let item = ItemID(service: "kt-test", account: "sam")
    private let keychain: TemporaryKeychain
    private let store: KeychainStore

    init() throws {
        keychain = try TemporaryKeychain()
        store = keychain.store()
    }

    @Test func addedItemIsOwnAndReadable() throws {
        #expect(try store.state(of: item) == .absent)

        try store.add(bytes("value-1"), as: item)

        #expect(try store.state(of: item) == .own)
        #expect(try store.read(item) == bytes("value-1"))
    }

    @Test func updateReplacesTheValueInPlace() throws {
        try store.add(bytes("value-1"), as: item)
        try store.update(bytes("value-2"), of: item)

        #expect(try store.read(item) == bytes("value-2"))
        #expect(try store.list(service: nil) == [item])
    }

    @Test func addingTwiceIsRejected() throws {
        try store.add(bytes("value-1"), as: item)

        #expect(throws: StoreError.duplicateItem) {
            try store.add(bytes("value-2"), as: item)
        }

        #expect(try store.read(item) == bytes("value-1"))
    }

    @Test func foreignItemIsRecognisedAndLeftAlone() throws {
        try keychain.addForeignItem(item)

        #expect(try store.state(of: item) == .foreign)
        #expect(try store.list(service: nil).isEmpty)

        #expect(throws: StoreError.notFound) {
            try store.read(item)
        }

        #expect(throws: StoreError.notFound) {
            try store.update(bytes("value"), of: item)
        }

        #expect(throws: StoreError.notFound) {
            try store.delete(item)
        }

        #expect(throws: StoreError.duplicateItem) {
            try store.add(bytes("value"), as: item)
        }
    }

    @Test func deleteRemovesTheItemOnce() throws {
        try store.add(bytes("value-1"), as: item)
        try store.delete(item)

        #expect(try store.state(of: item) == .absent)

        #expect(throws: StoreError.notFound) {
            try store.delete(item)
        }
    }

    @Test func missingItemIsReportedAsNotFound() {
        #expect(throws: StoreError.notFound) {
            try store.read(item)
        }

        #expect(throws: StoreError.notFound) {
            try store.update(bytes("value"), of: item)
        }
    }

    @Test func listIsSortedAndFilteredByService() throws {
        let other = ItemID(service: "kt-other", account: "sam")
        let second = ItemID(service: "kt-test", account: "alice")

        for entry in [item, other, second] {
            try store.add(bytes("value"), as: entry)
        }

        #expect(try store.list(service: nil) == [other, second, item])
        #expect(try store.list(service: "kt-test") == [second, item])
        #expect(try store.list(service: "kt-missing").isEmpty)
    }

    @Test func secretBytesSurviveUnchanged() throws {
        let binary: [UInt8] = [0x00, 0xFF, 0xFE, 0x0A, 0x80, 0x00]

        try store.add(binary, as: item)

        #expect(try store.read(item) == binary)
    }

    @Test func storesWithDifferentMarkersDoNotSeeEachOther() throws {
        let cacheStore = keychain.store(marker: AuthCache.marker)

        try store.add(bytes("value"), as: item)

        #expect(try cacheStore.state(of: item) == .foreign)
        #expect(try cacheStore.list(service: nil).isEmpty)
    }
}
