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
}

/// The process that asked for the secret. A hint for the user, not a guarantee: a process chooses its own name.
struct Requester: Equatable {
    static let maxNameLength = 64
    static let unknownName = "unknown process"

    let name: String
    let pid: pid_t

    static func parent() -> Requester {
        let pid = getppid()
        let name = executableName(of: pid) ?? unknownName

        return Requester(name: DisplayText.sanitized(name, maxLength: maxNameLength), pid: pid)
    }

    private static func executableName(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))

        guard length > 0 else {
            return nil
        }

        let path = String(decoding: buffer.prefix(Int(length)), as: UTF8.self)

        return path.split(separator: "/").last.map(String.init)
    }
}

enum PromptText {
    /// Completes the system dialog's sentence "<program> is trying to …".
    static func reason(for item: ItemID, requester: Requester) -> String {
        "read the secret “\(item.service)” (\(item.account)), requested by \(requester.name) (pid \(requester.pid))"
    }
}
