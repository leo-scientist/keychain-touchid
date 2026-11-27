struct ItemID: Hashable {
    let service: String
    let account: String
}

enum Command: Equatable {
    case get(ItemID, useCache: Bool)
    case set(ItemID)
    case delete(ItemID)
    case list(service: String?)
    case handover
    case receive
}

struct UsageError: Error, Equatable {
    let message: String
}

enum Arguments {
    static let maxNameLength = 128
    static let noCacheOption = "--no-cache"

    static let usage = """
        Usage:
          keytap set    <service> [account]               store a secret (piped stdin or hidden prompt)
          keytap get    [--no-cache] <service> [account]  print the secret after authentication
          keytap delete <service> [account]               remove the secret
          keytap list   [service]                         list stored secrets (names only)
          keytap --version                                print the version
          keytap handover                                 move the secrets to a new build (run by make update)
          keytap receive                                  take one secret from the build being replaced (run by handover)

        Account:    the current user's name when omitted
        Settings:   \(Settings.defaultPath) (root-owned, optional)
        Exit codes: 0 success, 1 error, 2 usage, 3 authentication denied, 4 not found
        """

    static func isHelpRequest(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else {
            return false
        }

        return ["help", "-h", "--help"].contains(first)
    }

    static func isVersionRequest(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else {
            return false
        }

        return ["version", "--version"].contains(first)
    }

    /// `defaultAccount` names the item when the account is omitted; nil when it could not be determined.
    static func parse(_ arguments: [String], defaultAccount: String?) throws -> Command {
        guard let name = arguments.first else {
            throw UsageError(message: "missing command")
        }

        let rest = Array(arguments.dropFirst())

        switch name {
        case "get":
            let (options, names) = try split(rest, allowedOptions: [noCacheOption])

            return .get(
                try item(from: names, command: name, defaultAccount: defaultAccount),
                useCache: !options.contains(noCacheOption)
            )
        case "set":
            let names = try split(rest, allowedOptions: []).names

            return .set(try item(from: names, command: name, defaultAccount: defaultAccount))
        case "delete":
            let names = try split(rest, allowedOptions: []).names

            return .delete(try item(from: names, command: name, defaultAccount: defaultAccount))
        case "list":
            return .list(service: try serviceFilter(from: try split(rest, allowedOptions: []).names))
        case "handover", "receive":
            guard rest.isEmpty else {
                throw UsageError(message: "“\(name)” takes no arguments")
            }

            return name == "handover" ? .handover : .receive
        default:
            throw UsageError(message: "unknown command “\(DisplayText.sanitized(name, maxLength: maxNameLength))”")
        }
    }

    /// Everything after a lone `--` is a name, so names may start with a dash.
    private static func split(
        _ arguments: [String],
        allowedOptions: Set<String>
    ) throws -> (options: Set<String>, names: [String]) {
        let terminator = arguments.firstIndex(of: "--") ?? arguments.endIndex
        let head = arguments[..<terminator]
        let tail = arguments[terminator...].dropFirst()
        let options = head.filter { $0.hasPrefix("-") }

        if let unknown = options.first(where: { !allowedOptions.contains($0) }) {
            throw UsageError(message: "unknown option “\(DisplayText.sanitized(unknown, maxLength: maxNameLength))”")
        }

        return (Set(options), head.filter { !$0.hasPrefix("-") } + tail)
    }

    private static func item(from names: [String], command: String, defaultAccount: String?) throws -> ItemID {
        guard (1...2).contains(names.count) else {
            throw UsageError(message: "“\(command)” takes <service> and an optional [account]")
        }

        guard let account = names.count == 2 ? names[1] : defaultAccount else {
            throw UsageError(message: "the current user's name could not be determined; give the [account]")
        }

        return try item(service: names[0], account: account)
    }

    /// The item for a pair of names, if they are ones the tool stores. See docs/commands.md#names.
    static func item(service: String, account: String) throws -> ItemID {
        ItemID(service: try self.service(service), account: try validated(account, label: "account"))
    }

    private static func serviceFilter(from names: [String]) throws -> String? {
        guard names.count <= 1 else {
            throw UsageError(message: "“list” takes at most one <service>")
        }

        return try names.first.map(service)
    }

    private static func service(_ value: String) throws -> String {
        let name = try validated(value, label: "service")

        guard !name.hasPrefix(AuthCache.servicePrefix) else {
            throw UsageError(message: "service must not start with the reserved prefix “\(AuthCache.servicePrefix)”")
        }

        return name
    }

    /// Names end up in the system authentication dialog, so they must not be able to disguise it.
    /// See docs/commands.md#names.
    private static func validated(_ value: String, label: String) throws -> String {
        guard !value.isEmpty else {
            throw UsageError(message: "\(label) must not be empty")
        }

        // Counted in scalars: a single character can carry any number of combining marks.
        guard value.unicodeScalars.count <= maxNameLength else {
            throw UsageError(message: "\(label) must not be longer than \(maxNameLength) characters")
        }

        guard !value.unicodeScalars.contains(where: DisplayText.isUnsafe) else {
            throw UsageError(message: "\(label) must not contain control or formatting characters")
        }

        return value
    }
}
