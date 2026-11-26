import Foundation

@main
struct KeychainTouchID {
    static let programName = "keychain-touchid"

    static func main() async {
        let code = await run(Array(CommandLine.arguments.dropFirst()))

        exit(code.rawValue)
    }

    private static func run(_ arguments: [String]) async -> ExitCode {
        guard !Arguments.isHelpRequest(arguments) else {
            print(Arguments.usage)

            return .success
        }

        do {
            let command = try Arguments.parse(arguments)
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

    private static func commands(with settings: Settings) -> Commands {
        Commands(
            store: KeychainStore(),
            authenticator: LocalAuthenticator(policy: settings.policy.localAuthenticationPolicy),
            requester: .parent(),
            readSecret: SecretInput.read,
            cache: AuthCache(
                records: KeychainStore(marker: AuthCache.marker, allowsUserInteraction: false),
                window: settings.cacheSeconds,
                session: .current(),
                now: Date.init
            ),
            output: Output(
                write: { try FileHandle.standardOutput.write(contentsOf: Data($0)) },
                note: report,
                isTerminal: isatty(STDOUT_FILENO) == 1
            )
        )
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
