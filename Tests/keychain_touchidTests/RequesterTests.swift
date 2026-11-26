import Darwin
import Testing
@testable import keychain_touchid

@Suite struct RequesterTests {
    @Test(arguments: ["\n", "\u{1B}", "\u{7F}", "\u{202E}", "\u{200B}", "\u{2028}", "\u{2029}"])
    func flagsCharactersThatCouldDisguiseThePrompt(character: String) {
        #expect(character.unicodeScalars.allSatisfy(DisplayText.isUnsafe))
    }

    @Test(arguments: ["a", " ", "-", "”", "ї", "🙂"])
    func allowsOrdinaryCharacters(character: String) {
        #expect(!character.unicodeScalars.contains(where: DisplayText.isUnsafe))
    }

    @Test func sanitizingReplacesUnsafeCharactersAndTruncates() {
        #expect(DisplayText.sanitized("zsh\n(pid 1)\u{202E}", maxLength: 64) == "zsh?(pid 1)?")
        #expect(DisplayText.sanitized("abcdef", maxLength: 3) == "abc…")
        #expect(DisplayText.sanitized("abc", maxLength: 3) == "abc")
        #expect(DisplayText.sanitized("a\u{0301}\u{0301}\u{0301}", maxLength: 2) == "a\u{0301}…")
    }

    @Test func parentIsTheProcessThatStartedTheTests() {
        let parent = Requester.parent()

        #expect(parent.pid == getppid())
        #expect(!parent.name.isEmpty)
        #expect(parent.name != Requester.unknownName)
        #expect(!parent.name.contains("/"))
    }

    @Test func reasonNamesTheItemAndTheRequester() {
        let reason = PromptText.reason(
            for: ItemID(service: "op-token", account: "sam"),
            requester: Requester(name: "zsh", pid: 4242)
        )

        #expect(reason == "read the secret “op-token” (sam), requested by zsh (pid 4242)")
    }
}
