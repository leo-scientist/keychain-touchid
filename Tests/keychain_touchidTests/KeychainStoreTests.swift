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

    @Test func replaceCreatesTheItemAnewWithTheNewValue() throws {
        try store.add(bytes("value-1"), as: item)
        try store.replace(item, with: bytes("value-2"))

        #expect(try store.read(item) == bytes("value-2"))
        #expect(try store.list(service: nil) == [item])
    }

    @Test func replaceRemovesWhateverHadTheName() throws {
        try keychain.addForeignItem(item)

        try store.replace(item, with: bytes("value"))

        #expect(try store.state(of: item) == .own)
        #expect(try store.read(item) == bytes("value"))
    }

    @Test func replaceCreatesAnItemThatDidNotExist() throws {
        try store.replace(item, with: bytes("value"))

        #expect(try store.read(item) == bytes("value"))
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
            try store.delete(item)
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

    @Test func removeAnyTakesOutWhateverHasTheName() throws {
        let other = ItemID(service: "kt-other", account: "sam")
        try store.add(bytes("value"), as: item)
        try keychain.addForeignItem(other)

        try store.removeAny(item)
        try store.removeAny(other)
        try store.removeAny(ItemID(service: "kt-missing", account: "sam"))

        #expect(try store.state(of: item) == .absent)
        #expect(try store.state(of: other) == .absent)
    }

    @Test func reportsWhetherTheKeychainIsLocked() throws {
        try store.add(bytes("value"), as: item)

        #expect(try !store.isLocked())

        keychain.lock()

        // Nothing is read here: reading a locked keychain is what makes the system offer to unlock it.
        #expect(try store.isLocked())
    }

    @Test func replaceOnALockedKeychainLeavesTheItem() throws {
        try store.add(bytes("value"), as: item)
        keychain.lock()

        #expect(throws: StoreError.locked) {
            try store.replace(item, with: bytes("other"))
        }

        // Looked at through its attributes only, which a locked keychain still shows without asking.
        #expect(try store.state(of: item) == .own)
    }

    @Test func operationsStayInsideTheStoresKeychain() throws {
        let elsewhere = try TemporaryKeychain()
        try elsewhere.addForeignItem(item)

        #expect(try store.state(of: item) == .absent)

        try store.replace(item, with: bytes("value"))
        try store.removeAny(item)

        #expect(try elsewhere.store().state(of: item) == .foreign)
    }

    @Test func storesWithDifferentMarkersDoNotSeeEachOther() throws {
        let cacheStore = keychain.store(marker: AuthCache.marker)

        try store.add(bytes("value"), as: item)

        #expect(try cacheStore.state(of: item) == .foreign)
        #expect(try cacheStore.list(service: nil).isEmpty)
    }
}

/// `replace` over a fake store, where an item can be put in the way between the removal and the creation.
@Suite struct SecretStoreTests {
    private let item = ItemID(service: "op-token", account: "sam")
    private let store = FakeStore()

    @Test func replaceRemovesAnItemPlantedAfterTheRemovalAndCreatesItsOwn() throws {
        var planted = false
        store.secrets[item] = bytes("old")
        store.beforeAdding = { [store] item in
            guard !planted else {
                return
            }

            // Another process creates an item with the tool's marker the moment the old one is gone.
            planted = true
            store.secrets[item] = bytes("attacker's item")
            store.unreadable.insert(item)
        }

        try store.replace(item, with: bytes("new"))

        #expect(store.secrets[item] == bytes("new"))
        #expect(store.unreadable.isEmpty)
        #expect(store.calls == ["removeAny", "add", "removeAny", "add"])
    }

    @Test func replaceOnALockedKeychainRemovesNothing() {
        store.secrets[item] = bytes("old")
        store.locked = true

        #expect(throws: StoreError.locked) {
            try store.replace(item, with: bytes("new"))
        }

        #expect(store.secrets[item] == bytes("old"))
        #expect(store.calls.isEmpty)
    }

    @Test func replaceGivesUpWhenAnItemIsPlantedOnEveryAttempt() {
        store.secrets[item] = bytes("old")
        store.beforeAdding = { [store] item in
            store.foreignItems.insert(item)
        }

        #expect(throws: StoreError.duplicateItem) {
            try store.replace(item, with: bytes("new"))
        }

        #expect(store.secrets[item] == nil)
        #expect(store.foreignItems == [item])
        #expect(store.calls == ["removeAny", "add", "removeAny", "add", "removeAny", "add"])
    }
}
