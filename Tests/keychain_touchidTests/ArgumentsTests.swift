import Testing
@testable import keychain_touchid

@Suite struct ArgumentsTests {
    private let item = ItemID(service: "op-token", account: "sam")

    @Test func parsesEachCommand() throws {
        #expect(try Arguments.parse(["get", "op-token", "sam"]) == .get(item, useCache: true))
        #expect(try Arguments.parse(["set", "op-token", "sam"]) == .set(item))
        #expect(try Arguments.parse(["delete", "op-token", "sam"]) == .delete(item))
        #expect(try Arguments.parse(["list"]) == .list(service: nil))
        #expect(try Arguments.parse(["list", "op-token"]) == .list(service: "op-token"))
    }

    @Test(arguments: [
        ["get", "--no-cache", "op-token", "sam"],
        ["get", "op-token", "--no-cache", "sam"],
        ["get", "op-token", "sam", "--no-cache"],
    ])
    func noCacheOptionIsAcceptedAnywhere(arguments: [String]) throws {
        #expect(try Arguments.parse(arguments) == .get(item, useCache: false))
    }

    @Test func namesAfterTerminatorMayStartWithDash() throws {
        let expected = Command.get(ItemID(service: "-svc", account: "--no-cache"), useCache: true)

        #expect(try Arguments.parse(["get", "--", "-svc", "--no-cache"]) == expected)
    }

    @Test(arguments: [
        [],
        ["frobnicate"],
        ["get"],
        ["get", "op-token"],
        ["get", "op-token", "sam", "extra"],
        ["set", "op-token"],
        ["delete"],
        ["list", "a", "b"],
        ["get", "--cache", "op-token", "sam"],
        ["set", "--no-cache", "op-token", "sam"],
        ["get", "-x", "op-token", "sam"],
    ])
    func rejectsMalformedInvocations(arguments: [String]) {
        #expect(throws: UsageError.self) {
            try Arguments.parse(arguments)
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
            try Arguments.parse(["get", "--", name, "sam"])
        }

        #expect(throws: UsageError.self) {
            try Arguments.parse(["get", "--", "op-token", name])
        }

        #expect(throws: UsageError.self) {
            try Arguments.parse(["list", "--", name])
        }
    }

    @Test func acceptsNamesAtTheLengthLimitAndNonASCII() throws {
        let longest = String(repeating: "a", count: Arguments.maxNameLength)

        #expect(try Arguments.parse(["set", longest, "користувач 🙂"])
            == .set(ItemID(service: longest, account: "користувач 🙂")))
    }

    @Test func rejectsServiceInTheCacheNamespace() {
        #expect(throws: UsageError.self) {
            try Arguments.parse(["set", AuthCache.servicePrefix + "op-token", "sam"])
        }
    }

    @Test func recognisesHelpRequests() {
        #expect(Arguments.isHelpRequest(["help"]))
        #expect(Arguments.isHelpRequest(["-h"]))
        #expect(Arguments.isHelpRequest(["--help", "get"]))
        #expect(!Arguments.isHelpRequest([]))
        #expect(!Arguments.isHelpRequest(["get", "--help", "x"]))
    }
}
