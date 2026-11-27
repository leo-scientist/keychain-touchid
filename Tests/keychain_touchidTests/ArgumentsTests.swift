import Testing
@testable import keychain_touchid

private func parse(_ arguments: [String], defaultAccount: String? = "sam") throws -> Command {
    try Arguments.parse(arguments, defaultAccount: defaultAccount)
}

@Suite struct ArgumentsTests {
    private let item = ItemID(service: "op-token", account: "sam")

    @Test func parsesEachCommand() throws {
        #expect(try parse(["get", "op-token", "sam"]) == .get(item, useCache: true))
        #expect(try parse(["set", "op-token", "sam"]) == .set(item))
        #expect(try parse(["delete", "op-token", "sam"]) == .delete(item))
        #expect(try parse(["list"]) == .list(service: nil))
        #expect(try parse(["list", "op-token"]) == .list(service: "op-token"))
        #expect(try parse(["handover"]) == .handover)
        #expect(try parse(["receive"]) == .receive)
    }

    @Test(arguments: [
        ["get", "--no-cache", "op-token", "sam"],
        ["get", "op-token", "--no-cache", "sam"],
        ["get", "op-token", "sam", "--no-cache"],
    ])
    func noCacheOptionIsAcceptedAnywhere(arguments: [String]) throws {
        #expect(try parse(arguments) == .get(item, useCache: false))
    }

    @Test func omittedAccountIsTheDefault() throws {
        #expect(try parse(["get", "op-token"]) == .get(item, useCache: true))
        #expect(try parse(["get", "--no-cache", "op-token"]) == .get(item, useCache: false))
        #expect(try parse(["set", "op-token"]) == .set(item))
        #expect(try parse(["delete", "op-token"]) == .delete(item))
    }

    @Test func omittedAccountWithoutDefaultIsAnError() {
        #expect(throws: UsageError.self) {
            try parse(["get", "op-token"], defaultAccount: nil)
        }
    }

    @Test func defaultAccountFollowsTheNameRules() {
        #expect(throws: UsageError.self) {
            try parse(["get", "op-token"], defaultAccount: "line\nbreak")
        }
    }

    @Test func namesAfterTerminatorMayStartWithDash() throws {
        let expected = Command.get(ItemID(service: "-svc", account: "--no-cache"), useCache: true)

        #expect(try parse(["get", "--", "-svc", "--no-cache"]) == expected)
    }

    @Test(arguments: [
        [],
        ["frobnicate"],
        ["get"],
        ["get", "op-token", "sam", "extra"],
        ["get", "--no-cache"],
        ["set"],
        ["delete"],
        ["list", "a", "b"],
        ["handover", "now"],
        ["handover", "--force"],
        ["receive", "op-token", "sam"],
        ["get", "--cache", "op-token", "sam"],
        ["set", "--no-cache", "op-token", "sam"],
        ["get", "-x", "op-token", "sam"],
    ])
    func rejectsMalformedInvocations(arguments: [String]) {
        #expect(throws: UsageError.self) {
            try parse(arguments)
        }
    }

    @Test(arguments: [
        "",
        "line\nbreak",
        "escape\u{1B}[2J",
        "bidi\u{202E}override",
        "separator\u{2028}",
        String(repeating: "a", count: Arguments.maxNameLength + 1),
        "a" + String(repeating: "\u{0301}", count: Arguments.maxNameLength),
    ])
    func rejectsNamesThatCouldDisguiseThePrompt(name: String) {
        #expect(throws: UsageError.self) {
            try parse(["get", "--", name, "sam"])
        }

        #expect(throws: UsageError.self) {
            try parse(["get", "--", "op-token", name])
        }

        #expect(throws: UsageError.self) {
            try parse(["list", "--", name])
        }
    }

    @Test func acceptsNamesAtTheLengthLimitAndNonASCII() throws {
        let longest = String(repeating: "a", count: Arguments.maxNameLength)

        #expect(
            try parse(["set", longest, "користувач 🙂"])
                == .set(ItemID(service: longest, account: "користувач 🙂")))
    }

    @Test func rejectsServiceInTheCacheNamespace() {
        #expect(throws: UsageError.self) {
            try parse(["set", AuthCache.servicePrefix + "op-token", "sam"])
        }
    }

    @Test func recognisesHelpRequests() {
        #expect(Arguments.isHelpRequest(["help"]))
        #expect(Arguments.isHelpRequest(["-h"]))
        #expect(Arguments.isHelpRequest(["--help", "get"]))
        #expect(!Arguments.isHelpRequest([]))
        #expect(!Arguments.isHelpRequest(["get", "--help", "x"]))
    }

    @Test func recognisesVersionRequests() {
        #expect(Arguments.isVersionRequest(["--version"]))
        #expect(Arguments.isVersionRequest(["version"]))
        #expect(!Arguments.isVersionRequest([]))
        #expect(!Arguments.isVersionRequest(["get", "--version"]))
    }
}
