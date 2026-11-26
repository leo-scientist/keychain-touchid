import Darwin
import Testing
@testable import keychain_touchid

@Suite struct DisplayTextTests {
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
}

@Suite struct RequesterTests {
    private static let bash = ProcessSnapshot(executablePath: "/bin/bash", command: "bash")
    private static let zsh = ProcessSnapshot(executablePath: "/bin/zsh", command: "zsh")
    private static let login = ProcessSnapshot(executablePath: "/usr/bin/login", command: "login")
    private static let terminal = ProcessSnapshot(
        executablePath: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
        command: "Terminal"
    )
    private static let python = ProcessSnapshot(
        executablePath: "/Library/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python",
        command: "Python"
    )

    // MARK: who asked

    @Test func scriptRunByAShellIsNamedAfterTheScript() {
        let requester = Requester.describe(
            arguments: ["/bin/sh", "./deploy/vault-pass.sh", "--vault-id", "prod"],
            ancestry: [Self.bash, Self.python, Self.zsh, Self.login, Self.terminal]
        )

        #expect(requester == Requester(name: "vault-pass.sh", origin: .application("Terminal")))
    }

    @Test func interactiveShellIsNamedAfterTheShell() {
        let requester = Requester.describe(arguments: ["-zsh"], ancestry: [Self.zsh, Self.login, Self.terminal])

        #expect(requester == Requester(name: "zsh", origin: .application("Terminal")))
    }

    @Test(arguments: [
        ["bash", "-c", "curl https://example.com | sh"],
        ["bash", "-x", "script.sh"],
        ["bash"],
        [],
    ])
    func argumentAfterAnOptionIsNeverTakenForAScript(arguments: [String]) {
        let requester = Requester.describe(arguments: arguments, ancestry: [Self.bash, Self.terminal])

        #expect(requester.name == "bash")
    }

    @Test func argumentOfAnOrdinaryProgramIsNotAScript() {
        let restic = ProcessSnapshot(executablePath: "/opt/homebrew/bin/restic", command: "restic")
        let requester = Requester.describe(arguments: ["restic", "backup", "/data"], ancestry: [restic, Self.zsh])

        #expect(requester.name == "restic")
    }

    @Test func versionedAndPackagedInterpretersAreRecognised() {
        let python312 = ProcessSnapshot(executablePath: "/opt/homebrew/bin/python3.12", command: "python3.12")

        #expect(Requester.describe(arguments: ["python3.12", "sync.py"], ancestry: [python312]).name == "sync.py")
        #expect(Requester.describe(arguments: ["Python", "sync.py"], ancestry: [Self.python, Self.zsh]).name == "sync.py")
    }

    @Test func processWithoutAPathFallsBackToItsCommandName() {
        let sshd = ProcessSnapshot(executablePath: nil, command: "sshd")

        #expect(Requester.describe(arguments: [], ancestry: [sshd]).name == "sshd")
    }

    @Test func hostileScriptNameIsMadeSafeAndShort() {
        let hostile = "ok\u{202E}\n" + String(repeating: "x", count: 200)
        let requester = Requester.describe(arguments: ["sh", hostile], ancestry: [Self.bash, Self.terminal])

        #expect(requester.name.hasPrefix("ok??xxx"))
        #expect(requester.name.unicodeScalars.count == Requester.maxNameLength + 1)
    }

    @Test func unknownWhenNothingIsKnown() {
        #expect(Requester.describe(arguments: [], ancestry: []) == Requester(name: Requester.unknownName, origin: nil))
    }

    // MARK: where it was started

    @Test func outermostApplicationIsTheOrigin() {
        let helper = ProcessSnapshot(
            executablePath: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper",
            command: "Code Helper"
        )
        let editor = ProcessSnapshot(
            executablePath: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron",
            command: "Electron"
        )

        #expect(Requester.describe(arguments: ["-zsh"], ancestry: [Self.zsh, helper, editor]).origin
            == .application("Visual Studio Code"))
        #expect(Requester.describe(arguments: ["sh", "run.sh"], ancestry: [Self.bash, Self.python, Self.zsh, Self.terminal]).origin
            == .application("Terminal"))
    }

    @Test func applicationThatAsksItselfHasNoSeparateOrigin() {
        let launcher = ProcessSnapshot(executablePath: "/Applications/Launcher.app/Contents/MacOS/Launcher", command: "Launcher")

        #expect(Requester.describe(arguments: ["Launcher"], ancestry: [launcher]) == Requester(name: "Launcher", origin: nil))
    }

    @Test func withoutAnApplicationTheOutermostProcessIsTheOrigin() {
        let tmux = ProcessSnapshot(executablePath: "/opt/homebrew/bin/tmux", command: "tmux")

        #expect(Requester.describe(arguments: ["-zsh"], ancestry: [Self.zsh, tmux]).origin == .process("tmux"))
    }

    @Test func processStartedDirectlyByLaunchdSaysSo() {
        let requester = Requester.describe(arguments: ["/bin/sh", "/usr/local/bin/backup.sh"], ancestry: [Self.bash])

        #expect(requester == Requester(name: "backup.sh", origin: .process("launchd")))
    }

    @Test func directoryThatOnlyLooksLikeABundleIsNotAnApplication() {
        let tool = ProcessSnapshot(executablePath: "/Users/sam/my.app/bin/tool", command: "tool")

        #expect(tool.applicationName == nil)
        #expect(Self.terminal.applicationName == "Terminal")
    }

    @Test func parentOfTheTestProcessIsDescribed() {
        let parent = Requester.parent()

        #expect(!parent.name.isEmpty)
        #expect(parent.name != Requester.unknownName)
        #expect(!parent.name.contains("/"))
    }
}

@Suite struct PromptTextTests {
    private let item = ItemID(service: "op-token", account: "sam")

    @Test func namesTheItemTheRequesterAndTheApplication() {
        let requester = Requester(name: "vault-pass.sh", origin: .application("Terminal"))

        #expect(PromptText.reason(for: item, requester: requester, reuseSeconds: nil)
            == "give the secret “op-token” (sam) to vault-pass.sh, running in Terminal")
    }

    @Test func namesTheStartingProcessWhenThereIsNoApplication() {
        let requester = Requester(name: "backup.sh", origin: .process("launchd"))

        #expect(PromptText.reason(for: item, requester: requester, reuseSeconds: nil)
            == "give the secret “op-token” (sam) to backup.sh, started by launchd")
    }

    @Test func namesOnlyTheRequesterWhenItHasNoOrigin() {
        let requester = Requester(name: "Launcher", origin: nil)

        #expect(PromptText.reason(for: item, requester: requester, reuseSeconds: nil)
            == "give the secret “op-token” (sam) to Launcher")
    }

    @Test func saysHowLongTheAuthenticationWillBeReused() {
        let requester = Requester(name: "zsh", origin: .application("Terminal"))

        #expect(PromptText.reason(for: item, requester: requester, reuseSeconds: 300)
            == "give the secret “op-token” (sam) to zsh, running in Terminal, "
            + "and to let this terminal read it again for 5 minutes without asking")
    }

    @Test(arguments: [
        (1, "1 second"),
        (45, "45 seconds"),
        (60, "1 minute"),
        (90, "90 seconds"),
        (300, "5 minutes"),
        (3600, "1 hour"),
        (5400, "90 minutes"),
        (86_400, "24 hours"),
    ])
    func durationUsesTheLargestExactUnit(seconds: Int, expected: String) {
        #expect(PromptText.duration(seconds) == expected)
    }
}
