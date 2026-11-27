import Foundation

enum AuthPolicy: String, Equatable {
    /// Touch ID, Apple Watch or the Mac password.
    case any
    /// Touch ID only.
    case biometry
}

struct SettingsError: Error, Equatable {
    let message: String
}

/// Settings come only from a root-owned file. See docs/settings.md.
struct Settings: Equatable {
    static let defaultPath = "/usr/local/etc/keytap.conf"
    static let maxCacheSeconds = 86_400
    static let defaults = Settings(cacheSeconds: 0, policy: .any)
    private static let maxFileSize = 64 * 1024

    /// How long a successful authentication is reused within one terminal session; 0 asks every time.
    let cacheSeconds: Int
    let policy: AuthPolicy

    static func load(from path: String = defaultPath, requiredOwner: uid_t = 0) throws -> Settings {
        // The checks and the read use one descriptor, so the file cannot be swapped in between.
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)

        guard descriptor >= 0 else {
            guard errno != ENOENT else {
                return defaults
            }

            throw SettingsError(message: "cannot open \(path): \(String(cString: strerror(errno)))")
        }

        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()

        guard fstat(descriptor, &info) == 0 else {
            throw SettingsError(message: "cannot inspect \(path): \(String(cString: strerror(errno)))")
        }

        try checkTrust(owner: info.st_uid, mode: info.st_mode, requiredOwner: requiredOwner)

        return try parse(String(decoding: try contents(of: file, at: path), as: UTF8.self))
    }

    private static func contents(of file: FileHandle, at path: String) throws -> Data {
        let data: Data

        do {
            data = try file.read(upToCount: maxFileSize + 1) ?? Data()
        } catch {
            throw SettingsError(message: "cannot read \(path): \(error.localizedDescription)")
        }

        guard data.count <= maxFileSize else {
            throw SettingsError(message: "\(path) is larger than \(maxFileSize) bytes")
        }

        return data
    }

    static func checkTrust(owner: uid_t, mode: mode_t, requiredOwner: uid_t = 0) throws {
        switch RootOwned.problem(owner: owner, mode: mode, type: S_IFREG, requiredOwner: requiredOwner) {
        case .wrongType:
            throw SettingsError(message: "the settings file is not a regular file")
        case .wrongOwner:
            throw SettingsError(message: "the settings file must be owned by user id \(requiredOwner)")
        case .writableByOthers:
            throw SettingsError(message: "the settings file must not be writable by group or others")
        case nil:
            return
        }
    }

    static func parse(_ text: String) throws -> Settings {
        let entries = try text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { index, line in try entry(from: line, lineNumber: index + 1) }
        let keys = entries.map(\.key)

        guard Set(keys).count == keys.count else {
            throw SettingsError(message: "a setting is given more than once")
        }

        let values = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })

        return Settings(
            cacheSeconds: try values["cache_seconds"].map(cacheSeconds) ?? defaults.cacheSeconds,
            policy: try values["policy"].map(policy) ?? defaults.policy
        )
    }

    private struct Entry {
        let key: String
        let value: String
        let lineNumber: Int
    }

    private static let knownKeys: Set<String> = ["cache_seconds", "policy"]

    private static func entry(from line: Substring, lineNumber: Int) throws -> Entry? {
        let content = line.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)

        guard !content.isEmpty else {
            return nil
        }

        let parts = content.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)

        guard parts.count == 2 else {
            throw SettingsError(message: "line \(lineNumber): expected “key = value”")
        }

        let key = parts[0].trimmingCharacters(in: .whitespaces)

        guard knownKeys.contains(key) else {
            throw SettingsError(message: "line \(lineNumber): unknown setting")
        }

        return Entry(key: key, value: parts[1].trimmingCharacters(in: .whitespaces), lineNumber: lineNumber)
    }

    private static func cacheSeconds(from entry: Entry) throws -> Int {
        guard let seconds = Int(entry.value), (0...maxCacheSeconds).contains(seconds) else {
            throw SettingsError(
                message: "line \(entry.lineNumber): cache_seconds must be a whole number from 0 to \(maxCacheSeconds)"
            )
        }

        return seconds
    }

    private static func policy(from entry: Entry) throws -> AuthPolicy {
        guard let policy = AuthPolicy(rawValue: entry.value) else {
            throw SettingsError(message: "line \(entry.lineNumber): policy must be “any” or “biometry”")
        }

        return policy
    }
}
