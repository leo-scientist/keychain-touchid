import Foundation

@main
struct KeychainTouchID {
    static let programName = "keytap"
    /// Matches the latest release in CHANGELOG.md and its git tag.
    static let version = "0.1.0"

    static func main() async {
        let code = await run(Array(CommandLine.arguments.dropFirst()))

        exit(code.rawValue)
    }

    private static func run(_ arguments: [String]) async -> ExitCode {
        guard !Arguments.isHelpRequest(arguments) else {
            print(Arguments.usage)

            return .success
        }

        guard !Arguments.isVersionRequest(arguments) else {
            print("\(programName) \(version)")

            return .success
        }

        do {
            let command = try Arguments.parse(arguments, defaultAccount: currentUserName())
            let settings = try Settings.load()
            try await commands(with: settings).run(command)

            return .success
        } catch {
            let failure = Failure(error)
            report(failure.message)

            if error is UsageError {
                printToStandardError(Arguments.usage)
            }

            return failure.code
        }
    }

    private static func commands(with settings: Settings) throws -> Commands {
        let keychain = try KeychainStore.loginKeychain()
        let authenticator = LocalAuthenticator(policy: settings.policy.localAuthenticationPolicy)
        let requester = Requester.parent()
        let output = Output(
            write: { try FileHandle.standardOutput.write(contentsOf: Data($0)) },
            note: report,
            isTerminal: isatty(STDOUT_FILENO) == 1
        )
        let handover = Handover(
            store: KeychainStore(keychain: keychain, allowsUserInteraction: false),
            authenticator: authenticator,
            requester: requester,
            successor: InstalledSuccessor(),
            output: output
        )

        return Commands(
            store: KeychainStore(keychain: keychain),
            authenticator: authenticator,
            requester: requester,
            readSecret: SecretInput.read,
            cache: AuthCache(
                records: KeychainStore(marker: AuthCache.marker, keychain: keychain, allowsUserInteraction: false),
                window: settings.cacheSeconds,
                session: .current(),
                now: Date.init
            ),
            handover: handover.run,
            readRecord: {
                try SecretInput.readAll(from: .standardInput, limit: HandoverRecord.maxEncodedSize + 1)
            },
            output: output
        )
    }

    /// From the user database rather than `$USER`, which the caller can set to anything.
    private static func currentUserName() -> String? {
        guard let entry = getpwuid(getuid()) else {
            return nil
        }

        return String(cString: entry.pointee.pw_name)
    }

    private static func report(_ message: String) {
        printToStandardError("\(programName): \(message)")
    }

    /// A caller may have closed stderr. There is nowhere left to report that, and the exit code still has to
    /// reach it, so a failed write is ignored.
    private static func printToStandardError(_ text: String) {
        try? FileHandle.standardError.write(contentsOf: Data("\(text)\n".utf8))
    }
}
