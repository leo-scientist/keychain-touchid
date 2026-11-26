import Foundation
import Testing
@testable import keychain_touchid

/// Real command flows over fake collaborators, recording what reaches the user.
private final class Harness {
    static let item = ItemID(service: "op-token", account: "sam")
    static let session = SessionScope(sessionID: 100, leaderStartedAt: 1_000, terminal: 7)

    let store = FakeStore()
    let records = FakeStore()
    let authenticator = FakeAuthenticator()
    var typedSecret = bytes("typed")
    var clock = Date(timeIntervalSince1970: 1_000_000)
    private(set) var written: [[UInt8]] = []
    private(set) var notes: [String] = []
    private(set) var secretRequests = 0

    func commands(window: Int = 0, session: SessionScope? = Harness.session, isTerminal: Bool = false) -> Commands {
        Commands(
            store: store,
            authenticator: authenticator,
            requester: Requester(name: "zsh", origin: .application("Terminal")),
            readSecret: { [self] _ in
                secretRequests += 1

                return typedSecret
            },
            cache: AuthCache(records: records, window: window, session: session, now: { [self] in clock }),
            output: Output(
                write: { [self] in written.append($0) },
                note: { [self] in notes.append($0) },
                isTerminal: isTerminal
            )
        )
    }
}

@Suite struct CommandsTests {
    private let item = Harness.item
    private let harness = Harness()

    // MARK: get

    @Test func getPrintsExactBytesAfterAuthentication() async throws {
        harness.store.secrets[item] = [0x00, 0xFF, 0x0A]

        try await harness.commands().run(.get(item, useCache: true))

        #expect(harness.written == [[0x00, 0xFF, 0x0A]])
        #expect(harness.authenticator.reasons == ["give the secret “op-token” (sam) to zsh, running in Terminal"])
    }

    @Test func getAppendsNewlineOnlyForATerminal() async throws {
        harness.store.secrets[item] = bytes("token")

        try await harness.commands(isTerminal: true).run(.get(item, useCache: true))

        #expect(harness.written == [bytes("token\n")])
    }

    @Test func deniedAuthenticationNeverReachesTheKeychain() async {
        harness.store.secrets[item] = bytes("token")
        harness.authenticator.error = AuthenticationError(message: "cancelled")

        await #expect(throws: AuthenticationError(message: "cancelled")) {
            try await harness.commands(window: 60).run(.get(item, useCache: true))
        }

        #expect(!harness.store.calls.contains("read"))
        #expect(harness.written.isEmpty)
        #expect(!harness.records.calls.contains("add"))
    }

    @Test func missingItemDoesNotAskForAuthentication() async {
        await #expect(throws: StoreError.notFound) {
            try await harness.commands().run(.get(item, useCache: true))
        }

        #expect(harness.authenticator.reasons.isEmpty)
        #expect(harness.written.isEmpty)
    }

    @Test func foreignItemIsNotFound() async {
        harness.store.foreignItems = [item]

        await #expect(throws: StoreError.notFound) {
            try await harness.commands().run(.get(item, useCache: true))
        }

        #expect(harness.authenticator.reasons.isEmpty)
    }

    // MARK: set, delete, list

    @Test func setCreatesANewItemWithoutAuthentication() async throws {
        try await harness.commands().run(.set(item))

        #expect(harness.store.secrets[item] == bytes("typed"))
        #expect(harness.store.calls == ["add"])
        #expect(harness.authenticator.reasons.isEmpty)
    }

    @Test func setUpdatesAnOwnItemInPlace() async throws {
        harness.store.secrets[item] = bytes("old")

        try await harness.commands().run(.set(item))

        #expect(harness.store.secrets[item] == bytes("typed"))
        #expect(harness.store.calls == ["update"])
        #expect(harness.authenticator.reasons.isEmpty)
    }

    @Test func setRefusesAForeignItemBeforeAskingForTheSecret() async {
        harness.store.foreignItems = [item]

        await #expect(throws: StoreError.duplicateItem) {
            try await harness.commands().run(.set(item))
        }

        #expect(harness.secretRequests == 0)
        #expect(harness.store.calls.isEmpty)
    }

    @Test func deleteRemovesTheItemAndItsRememberedAuthentication() async throws {
        harness.store.secrets[item] = bytes("token")
        harness.records.secrets[AuthCache.recordID(for: item)] = bytes("record")

        try await harness.commands().run(.delete(item))

        #expect(harness.store.secrets.isEmpty)
        #expect(harness.records.secrets.isEmpty)
        #expect(harness.authenticator.reasons.isEmpty)
        #expect(harness.notes.isEmpty)
    }

    @Test func deleteOfAMissingItemIsNotFound() async {
        await #expect(throws: StoreError.notFound) {
            try await harness.commands().run(.delete(item))
        }
    }

    @Test func listPrintsOneItemPerLineWithoutAuthentication() async throws {
        harness.store.secrets[item] = bytes("token")
        harness.store.secrets[ItemID(service: "aws", account: "ci")] = bytes("key")

        try await harness.commands().run(.list(service: nil))

        #expect(harness.written == [bytes("aws\tci\nop-token\tsam\n")])
        #expect(harness.authenticator.reasons.isEmpty)
        #expect(!harness.store.calls.contains("read"))
    }

    @Test func listKeepsAnItemWithAHostileNameOnOneLine() async throws {
        harness.store.secrets[ItemID(service: "evil\nforged\trow", account: "\u{1B}[2Jme")] = bytes("x")

        try await harness.commands().run(.list(service: nil))

        #expect(harness.written == [bytes("evil?forged?row\t?[2Jme\n")])
    }

    // MARK: reused authentication

    @Test func disabledCacheIsNeitherReadNorWritten() async throws {
        harness.store.secrets[item] = bytes("token")

        try await harness.commands(window: 0).run(.get(item, useCache: true))
        try await harness.commands(window: 0).run(.get(item, useCache: true))

        #expect(harness.records.calls.isEmpty)
        #expect(harness.authenticator.reasons.count == 2)
    }

    @Test func secondReadWithinTheWindowSkipsAuthentication() async throws {
        harness.store.secrets[item] = bytes("token")
        let commands = harness.commands(window: 60)

        try await commands.run(.get(item, useCache: true))
        harness.clock += 30
        try await commands.run(.get(item, useCache: true))

        #expect(harness.authenticator.reasons.count == 1)
        #expect(harness.written == [bytes("token"), bytes("token")])
        #expect(harness.notes == ["authentication reused from 30 s ago"])
    }

    @Test func promptSaysWhenTheAuthenticationWillBeReused() async throws {
        harness.store.secrets[item] = bytes("token")

        try await harness.commands(window: 300).run(.get(item, useCache: true))
        try await harness.commands(window: 300, session: nil).run(.get(item, useCache: true))
        try await harness.commands(window: 0).run(.get(item, useCache: false))

        let reuseNotice = "let this terminal read it again for 5 minutes"

        #expect(harness.authenticator.reasons.map { $0.contains(reuseNotice) } == [true, false, false])
    }

    @Test func readAfterTheWindowAuthenticatesAgain() async throws {
        harness.store.secrets[item] = bytes("token")
        let commands = harness.commands(window: 60)

        try await commands.run(.get(item, useCache: true))
        harness.clock += 61
        try await commands.run(.get(item, useCache: true))

        #expect(harness.authenticator.reasons.count == 2)
    }

    @Test func reuseDoesNotExtendTheWindow() async throws {
        harness.store.secrets[item] = bytes("token")
        let commands = harness.commands(window: 60)

        try await commands.run(.get(item, useCache: true))
        harness.clock += 30
        try await commands.run(.get(item, useCache: true))
        harness.clock += 31
        try await commands.run(.get(item, useCache: true))

        #expect(harness.authenticator.reasons.count == 2)
        #expect(harness.records.calls.filter { $0 == "add" }.count == 2)
    }

    @Test func changedSecretInvalidatesTheRememberedAuthentication() async throws {
        harness.store.secrets[item] = bytes("token")
        let commands = harness.commands(window: 60)

        try await commands.run(.get(item, useCache: true))
        harness.store.secrets[item] = bytes("replaced by someone")
        try await commands.run(.get(item, useCache: true))

        #expect(harness.authenticator.reasons.count == 2)
    }

    @Test func otherSessionAuthenticatesAgain() async throws {
        harness.store.secrets[item] = bytes("token")
        let otherTab = SessionScope(sessionID: 200, leaderStartedAt: 2_000, terminal: 8)

        try await harness.commands(window: 60).run(.get(item, useCache: true))
        try await harness.commands(window: 60, session: otherTab).run(.get(item, useCache: true))

        #expect(harness.authenticator.reasons.count == 2)
    }

    @Test func processWithoutATerminalNeverUsesTheCache() async throws {
        harness.store.secrets[item] = bytes("token")
        let commands = harness.commands(window: 60, session: nil)

        try await commands.run(.get(item, useCache: true))
        try await commands.run(.get(item, useCache: true))

        #expect(harness.authenticator.reasons.count == 2)
        #expect(harness.records.calls.isEmpty)
    }

    @Test func noCacheOptionAlwaysAuthenticates() async throws {
        harness.store.secrets[item] = bytes("token")
        let commands = harness.commands(window: 60)

        try await commands.run(.get(item, useCache: true))
        try await commands.run(.get(item, useCache: false))

        #expect(harness.authenticator.reasons.count == 2)
    }

    @Test func failureToRememberDoesNotFailTheRead() async throws {
        harness.store.secrets[item] = bytes("token")
        harness.records.foreignItems = [AuthCache.recordID(for: item)]

        try await harness.commands(window: 60).run(.get(item, useCache: true))

        #expect(harness.written == [bytes("token")])
        #expect(harness.notes.count == 1)
    }
}
