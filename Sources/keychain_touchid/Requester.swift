import Darwin

/// See docs/authentication.md#text-safe-to-display.
enum DisplayText {
    static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator:
            true
        default:
            false
        }
    }

    static func sanitized(_ text: String, maxLength: Int) -> String {
        let scalars = text.unicodeScalars.map { isUnsafe($0) ? "?" : $0 }

        // Counted in scalars: a single character can carry any number of combining marks.
        guard scalars.count > maxLength else {
            return String(String.UnicodeScalarView(scalars))
        }

        return String(String.UnicodeScalarView(scalars.prefix(maxLength))) + "…"
    }

    /// An item's names for a message. They may come back from the Keychain, where anyone can write them.
    static func described(_ item: ItemID) -> String {
        let service = sanitized(item.service, maxLength: Arguments.maxNameLength)
        let account = sanitized(item.account, maxLength: Arguments.maxNameLength)

        return "“\(service)” (\(account))"
    }
}

/// What asked for the secret and where it was started from. A hint for the user, not a guarantee: a process
/// chooses its own name and arguments. See docs/authentication.md#the-requesting-process.
struct Requester: Equatable {
    enum Origin: Equatable {
        /// The application the user sees, such as a terminal or an editor.
        case application(String)
        /// The outermost ancestor, when no application is among them.
        case process(String)
    }

    static let maxNameLength = 64
    static let unknownName = "unknown process"
    static let launchdName = "launchd"

    /// The script an interpreter is running, otherwise the program's name.
    let name: String
    /// `nil` when the requester is itself the outermost thing there is to name.
    let origin: Origin?

    static func parent() -> Requester {
        let pid = getppid()

        // The process that started this one has exited, so launchd adopted it.
        guard pid > 1 else {
            return Requester(name: launchdName, origin: nil)
        }

        return describe(arguments: ProcessAncestry.arguments(of: pid), ancestry: ProcessAncestry.chain(from: pid))
    }

    /// - Parameters:
    ///   - arguments: what the nearest process was started with.
    ///   - ancestry: the nearest process first, then its ancestors, without launchd.
    static func describe(arguments: [String], ancestry: [ProcessSnapshot]) -> Requester {
        guard let nearest = ancestry.first else {
            return Requester(name: unknownName, origin: nil)
        }

        let name = scriptName(of: nearest, arguments: arguments) ?? nearest.name

        return Requester(name: displayed(name), origin: origin(of: ancestry))
    }

    private static let interpreters: Set<String> = [
        "sh", "bash", "zsh", "dash", "ksh", "fish", "csh", "tcsh",
        "python", "python3", "ruby", "perl", "node", "osascript",
    ]

    /// Only an interpreter's first argument names a script, and only when no option comes before it:
    /// after an option such as `-c` the next argument may be a whole command line.
    private static func scriptName(of process: ProcessSnapshot, arguments: [String]) -> String? {
        let program = process.name.lowercased()

        guard interpreters.contains(program) || program.hasPrefix("python"),
            arguments.count > 1,
            !arguments[1].hasPrefix("-")
        else {
            return nil
        }

        return arguments[1].split(separator: "/").last.map(String.init)
    }

    private static func origin(of ancestry: [ProcessSnapshot]) -> Origin? {
        // The outermost application is the one the user sees; nearer ones are helpers or packaged interpreters.
        if let index = ancestry.lastIndex(where: { $0.applicationName != nil }),
            let application = ancestry[index].applicationName
        {
            return index == 0 ? nil : .application(displayed(application))
        }

        guard ancestry.count > 1, let outermost = ancestry.last else {
            return .process(launchdName)
        }

        return .process(displayed(outermost.name))
    }

    private static func displayed(_ name: String) -> String {
        DisplayText.sanitized(name, maxLength: maxNameLength)
    }
}

enum PromptText {
    /// Completes the system dialog's sentence "<program> is trying to …". See docs/authentication.md#wording.
    ///
    /// - Parameter reuseSeconds: how long this authentication will be reused, when the reuse window applies.
    static func reason(for item: ItemID, requester: Requester, reuseSeconds: Int?) -> String {
        let request =
            "give the secret “\(item.service)” (\(item.account)) to \(requester.name)"
            + description(of: requester.origin)

        guard let reuseSeconds else {
            return request
        }

        return request + ", and to let this terminal read it again for \(duration(reuseSeconds)) without asking"
    }

    /// For `handover`, which gives every secret to the build that replaces this one.
    static func handoverReason(count: Int, requester: Requester) -> String {
        "hand its \(counted(count, "secret")) over to the new build that is being installed, "
            + "at the request of \(requester.name)" + description(of: requester.origin)
    }

    static func duration(_ seconds: Int) -> String {
        let secondsPerMinute = 60
        let secondsPerHour = 3600

        if seconds % secondsPerHour == 0 {
            return counted(seconds / secondsPerHour, "hour")
        }

        if seconds % secondsPerMinute == 0 {
            return counted(seconds / secondsPerMinute, "minute")
        }

        return counted(seconds, "second")
    }

    private static func description(of origin: Requester.Origin?) -> String {
        switch origin {
        case let .application(name):
            ", running in \(name)"
        case let .process(name):
            ", started by \(name)"
        case nil:
            ""
        }
    }

    private static func counted(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }
}
