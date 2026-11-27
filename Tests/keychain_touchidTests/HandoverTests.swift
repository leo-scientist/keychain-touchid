import Foundation
import Testing
@testable import keychain_touchid

/// Stands in for the new build. Like the real one, it only creates an item and refuses when one is in place.
private final class FakeSuccessor: Successor {
    var verificationError: HandoverError?
    /// How many more times storing an item fails before it works.
    var failuresLeft: [ItemID: Int] = [:]
    /// Runs just before every attempt, as a process racing the hand-over would.
    var beforeStoring: (ItemID) -> Void = { _ in }
    private(set) var attempts: [ItemID: Int] = [:]
    private let keychain: FakeStore

    init(keychain: FakeStore) {
        self.keychain = keychain
    }

    func verify() throws {
        if let verificationError {
            throw verificationError
        }
    }

    func store(_ secret: [UInt8], as item: ItemID) throws {
        attempts[item, default: 0] += 1
        beforeStoring(item)

        if let left = failuresLeft[item], left > 0 {
            failuresLeft[item] = left - 1

            throw HandoverError(message: "refused")
        }

        guard keychain.state(of: item) == .absent else {
            throw StoreError.duplicateItem
        }

        // What the successor creates is its own: the build that handed it over can no longer read it.
        keychain.secrets[item] = secret
        keychain.unreadable.insert(item)
    }
}

@Suite struct HandoverTests {
    private final class Notes {
        var lines: [String] = []
    }

    private let first = ItemID(service: "aws", account: "ci")
    private let second = ItemID(service: "op-token", account: "sam")
    private let original: [ItemID: [UInt8]]
    private let keychain = FakeStore()
    private let authenticator = FakeAuthenticator()
    private let successor: FakeSuccessor
    private let notes = Notes()

    init() {
        original = [first: [0x00, 0xFF, 0x0D], second: bytes("token")]
        successor = FakeSuccessor(keychain: keychain)
        keychain.secrets = original
    }

    private var handover: Handover {
        Handover(
            store: keychain,
            authenticator: authenticator,
            requester: Requester(name: "make", origin: .application("Terminal")),
            successor: successor,
            output: Output(write: { _ in }, note: { [notes] in notes.lines.append($0) }, isTerminal: false)
        )
    }

    // MARK: the ordinary update

    @Test func everySecretMovesToTheSuccessorUnchanged() async throws {
        try await handover.run()

        #expect(keychain.secrets == original)
        #expect(keychain.unreadable == [first, second])
        #expect(notes.lines == ["handed over 2 of 2 secrets to the new build"])
    }

    @Test func oneAuthenticationCoversAllSecretsAndSaysSo() async throws {
        try await handover.run()

        #expect(
            authenticator.reasons == [
                "hand its 2 secrets over to the new build that is being installed, "
                    + "at the request of make, running in Terminal"
            ])
    }

    @Test func nothingHappensWithoutSecrets() async throws {
        keychain.secrets = [:]
        successor.verificationError = HandoverError(message: "missing")

        try await handover.run()

        #expect(authenticator.reasons.isEmpty)
        #expect(notes.lines == ["no secrets to hand over"])
    }

    // MARK: stopping before anything is read

    @Test func untrustedSuccessorStopsBeforeAuthentication() async {
        successor.verificationError = HandoverError(message: "must be owned by user id 0")

        await #expect(throws: HandoverError(message: "must be owned by user id 0")) {
            try await handover.run()
        }

        #expect(authenticator.reasons.isEmpty)
        #expect(!keychain.calls.contains("read"))
    }

    @Test func lockedKeychainStopsTheUpdateInsteadOfSkippingEverything() async {
        keychain.locked = true
        keychain.unreadable = [first, second]

        await #expect(throws: HandoverError.self) {
            try await handover.run()
        }

        #expect(authenticator.reasons.isEmpty)
        #expect(!keychain.calls.contains("read"))
        #expect(keychain.secrets == original)
    }

    @Test func refusedAuthenticationLeavesEverythingInPlace() async {
        authenticator.error = AuthenticationError(message: "denied")

        await #expect(throws: AuthenticationError(message: "denied")) {
            try await handover.run()
        }

        #expect(keychain.secrets == original)
        #expect(keychain.unreadable.isEmpty)
        #expect(!keychain.calls.contains("read"))
    }

    // MARK: secrets that stay

    @Test func secretThisBuildMayNotReadIsLeftAlone() async throws {
        keychain.unreadable = [first]

        try await handover.run()

        #expect(successor.attempts == [second: 1])
        #expect(keychain.secrets == original)
        #expect(notes.lines.first == "handed over 1 of 2 secrets to the new build")
        #expect(notes.lines.last?.hasSuffix(": “aws” (ci)") == true)
    }

    @Test func itemWithANameTheToolWouldNotStoreIsLeftAloneAndShownSafely() async throws {
        let hostile = ItemID(service: "evil\n\u{1B}[2J", account: "x")
        keychain.secrets[hostile] = bytes("planted")

        try await handover.run()

        #expect(successor.attempts[hostile] == nil)
        #expect(keychain.secrets[hostile] == bytes("planted"))
        #expect(notes.lines.last?.hasSuffix(": “evil??[2J” (x)") == true)
    }

    // MARK: an item planted during the hand-over

    @Test func plantedItemIsRemovedAndNeverReceivesTheSecret() async throws {
        var planted = false
        successor.beforeStoring = { [keychain, second] item in
            guard item == second, !planted else {
                return
            }

            // Another process creates an item with the tool's marker the moment the real one is gone.
            planted = true
            keychain.secrets[second] = bytes("attacker's item")
            keychain.unreadable.insert(second)
        }

        try await handover.run()

        #expect(successor.attempts[second] == 2)
        #expect(keychain.secrets == original)
    }

    @Test func plantedUnmarkedItemIsRemovedToo() async throws {
        var planted = false
        successor.beforeStoring = { [keychain, first] item in
            guard item == first, !planted else {
                return
            }

            planted = true
            keychain.foreignItems.insert(first)
        }

        try await handover.run()

        #expect(keychain.foreignItems.isEmpty)
        #expect(keychain.secrets == original)
        #expect(keychain.unreadable == [first, second])
    }

    @Test func itemPlantedOnEveryAttemptStopsTheUpdateWithoutLosingAnything() async {
        successor.beforeStoring = { [keychain, second] item in
            if item == second {
                keychain.foreignItems.insert(second)
            }
        }

        await #expect(throws: StoreError.duplicateItem) {
            try await handover.run()
        }

        #expect(successor.attempts[second] == 3)
        #expect(keychain.secrets == original)
        #expect(keychain.unreadable.isEmpty)
        #expect(keychain.foreignItems.isEmpty)
    }

    // MARK: all or nothing

    @Test func failureOnALaterSecretTakesBackTheEarlierOnes() async {
        successor.failuresLeft = [second: .max]

        await #expect(throws: HandoverError(message: "refused")) {
            try await handover.run()
        }

        #expect(successor.attempts == [first: 1, second: 3])
        #expect(keychain.secrets == original)
        #expect(keychain.unreadable.isEmpty)
        #expect(notes.lines == ["the hand-over was undone; every secret is back with this build"])
    }

    @Test func readFailureOnALaterSecretTakesBackTheEarlierOnes() async {
        successor.beforeStoring = { [keychain, second] _ in
            // The second secret disappears after the listing, while the first is being handed over.
            keychain.secrets[second] = nil
        }

        await #expect(throws: StoreError.notFound) {
            try await handover.run()
        }

        #expect(successor.attempts == [first: 1])
        #expect(keychain.secrets[first] == original[first])
        #expect(keychain.unreadable.isEmpty)
    }

    @Test func passingFailureOfTheSuccessorIsRetried() async throws {
        successor.failuresLeft = [first: 1]

        try await handover.run()

        #expect(successor.attempts == [first: 2, second: 1])
        #expect(keychain.unreadable == [first, second])
    }

    @Test func secretThatCannotBeTakenBackIsNamedInTheError() async throws {
        successor.failuresLeft = [second: .max]
        keychain.failingAdds = [first]

        let error = try await #require(throws: HandoverError.self) {
            try await handover.run()
        }

        #expect(error.message == "refused; could not be taken back: “aws” (ci); store them again with set")
        // Taking it back removed what the successor had created, and then could not create it anew.
        #expect(keychain.secrets[first] == nil)
        #expect(keychain.secrets[second] == bytes("token"))
        #expect(notes.lines.isEmpty)
    }
}

@Suite struct HandoverRecordTests {
    private let secret: [UInt8] = [0x00, 0xFF, 0x0D, 0x0A]

    @Test func roundTripKeepsEveryByte() throws {
        let item = ItemID(service: "op-token", account: "sam")
        let decoded = try HandoverRecord.decode(HandoverRecord.encode(secret, for: item))

        #expect(decoded.item == item)
        #expect(decoded.secret == secret)
    }

    @Test(arguments: ["caf\u{E9}", "cafe\u{301}", "\u{439}\u{457}", "\u{D55C}"])
    func namesKeepTheirExactSpelling(name: String) throws {
        let decoded = try HandoverRecord.decode(
            HandoverRecord.encode(secret, for: ItemID(service: name, account: name)))

        // Swift compares strings by meaning; the Keychain compares bytes, so the bytes are what must match.
        #expect(Array(decoded.item.service.utf8) == Array(name.utf8))
        #expect(Array(decoded.item.account.utf8) == Array(name.utf8))
    }

    @Test func encodingIsThreeLengthPrefixedFields() {
        let encoded = HandoverRecord.encode([0x41], for: ItemID(service: "ab", account: "c"))

        #expect(encoded == [0, 0, 0, 2, 0x61, 0x62, 0, 0, 0, 1, 0x63, 0, 0, 0, 1, 0x41])
    }

    @Test func largestSecretAndLongestNamesFit() throws {
        let name = String(repeating: "\u{1F642}", count: Arguments.maxNameLength)
        let largest = [UInt8](repeating: 0x61, count: SecretInput.maxPipedBytes)
        let encoded = HandoverRecord.encode(largest, for: ItemID(service: name, account: name))

        #expect(encoded.count == HandoverRecord.maxEncodedSize)
        #expect(try HandoverRecord.decode(encoded).secret == largest)
    }

    @Test(
        arguments: [
            [],
            [0, 0, 0, 2, 0x61],
            [0, 0, 0, 1, 0x61, 0, 0, 0, 1, 0x62],
            [0, 0, 0, 1, 0x61, 0, 0, 0, 1, 0x62, 0, 0, 0, 1, 0x63, 0x64],
            [0, 0, 0, 1, 0x61, 0, 0, 0, 1, 0x62, 0, 0, 0, 0],
            [0, 0, 0, 1, 0xFF, 0, 0, 0, 1, 0x62, 0, 0, 0, 1, 0x63],
            [0, 0, 0, 0, 0, 0, 0, 1, 0x62, 0, 0, 0, 1, 0x63],
            [0, 0, 0, 1, 0x0A, 0, 0, 0, 1, 0x62, 0, 0, 0, 1, 0x63],
            [0xFF, 0xFF, 0xFF, 0xFF, 0x61],
        ] as [[UInt8]])
    func malformedRecordIsRefused(bytes: [UInt8]) {
        #expect(throws: (any Error).self) {
            try HandoverRecord.decode(bytes)
        }
    }

    @Test func oversizedSecretIsRefused() {
        let tooLarge = [UInt8](repeating: 0x61, count: SecretInput.maxPipedBytes + 1)

        #expect(throws: HandoverError.self) {
            try HandoverRecord.decode(HandoverRecord.encode(tooLarge, for: ItemID(service: "a", account: "b")))
        }
    }
}

@Suite struct InstalledSuccessorTests {
    private let item = ItemID(service: "caf\u{E9}", account: "\u{439}\u{457}")
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychain-touchid-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A stand-in for the new build: records how it was called and what it was fed.
    private func successor(script body: String? = nil, permissions: Int = 0o755) throws -> InstalledSuccessor {
        let path = directory.appendingPathComponent("successor").path
        let script =
            body ?? """
                #!/bin/sh
                printf '%s\\n' "$@" > "\(directory.path)/arguments"
                cat > "\(directory.path)/input"
                """
        try Data(script.utf8).write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)

        return InstalledSuccessor(path: path, requiredOwner: getuid())
    }

    private func recorded(_ name: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: directory.appendingPathComponent(name)))
    }

    @Test func recordIsPipedToTheReceiveCommandWithNamesByteForByte() throws {
        defer {
            cleanUp()
        }

        try successor().store([0x00, 0xFF, 0x0D], as: item)

        let received = try HandoverRecord.decode(try recorded("input"))

        #expect(try recorded("arguments") == bytes("receive\n"))
        #expect(Array(received.item.service.utf8) == [0x63, 0x61, 0x66, 0xC3, 0xA9])
        #expect(Array(received.item.account.utf8) == [0xD0, 0xB9, 0xD1, 0x97])
        #expect(received.secret == [0x00, 0xFF, 0x0D])
    }

    @Test func failureOfTheSuccessorIsAnError() throws {
        defer {
            cleanUp()
        }

        let failing = try successor(script: "#!/bin/sh\ncat > /dev/null\nexit 1\n")

        #expect(throws: HandoverError.self) {
            try failing.store(bytes("token"), as: item)
        }
    }

    @Test func successorThatExitsWithoutReadingIsAnErrorNotACrash() throws {
        defer {
            cleanUp()
        }

        let impatient = try successor(script: "#!/bin/sh\nexit 3\n")
        let largest = [UInt8](repeating: 0x61, count: SecretInput.maxPipedBytes)

        #expect(throws: HandoverError.self) {
            try impatient.store(largest, as: item)
        }
    }

    @Test func acceptsASuccessorOnlyItsOwnerCanChange() throws {
        defer {
            cleanUp()
        }

        try successor().verify()
    }

    @Test func rejectsASuccessorOthersCanWrite() throws {
        defer {
            cleanUp()
        }

        let writable = try successor(permissions: 0o777)

        #expect(throws: HandoverError.self) {
            try writable.verify()
        }
    }

    @Test func rejectsASuccessorOwnedBySomeoneElse() throws {
        defer {
            cleanUp()
        }

        let path = try successor().path

        #expect(throws: HandoverError.self) {
            try InstalledSuccessor(path: path, requiredOwner: getuid() + 1).verify()
        }
    }

    @Test func rejectsADirectoryOthersCanWrite() throws {
        defer {
            cleanUp()
        }

        let present = try successor()
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directory.path)

        #expect(throws: HandoverError.self) {
            try present.verify()
        }
    }

    @Test func rejectsASymbolicLinkAndAMissingSuccessor() throws {
        defer {
            cleanUp()
        }

        let target = try successor().path
        let link = directory.appendingPathComponent("link").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)

        #expect(throws: HandoverError(message: "the new build \(link) is not a regular file")) {
            try InstalledSuccessor(path: link, requiredOwner: getuid()).verify()
        }

        #expect(throws: HandoverError.self) {
            try InstalledSuccessor(path: directory.appendingPathComponent("absent").path, requiredOwner: getuid())
                .verify()
        }
    }
}
