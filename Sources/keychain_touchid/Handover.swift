import Foundation

struct HandoverError: Error, Equatable {
    let message: String
}

/// One secret on its way to the successor: both names and the value, as exact bytes.
///
/// The names travel here rather than as program arguments: Foundation rewrites the characters of arguments,
/// and the Keychain compares names byte for byte.
enum HandoverRecord {
    /// A name has at most `Arguments.maxNameLength` scalars of at most four bytes each.
    private static let maxNameBytes = 4 * Arguments.maxNameLength
    private static let lengthSize = MemoryLayout<UInt32>.size
    private static let fieldCount = 3

    static let maxEncodedSize = fieldCount * lengthSize + 2 * maxNameBytes + SecretInput.maxPipedBytes

    /// Service, account, secret: each a 4-byte big-endian length followed by that many bytes.
    static func encode(_ secret: [UInt8], for item: ItemID) -> [UInt8] {
        [Array(item.service.utf8), Array(item.account.utf8), secret].flatMap { field in
            withUnsafeBytes(of: UInt32(field.count).bigEndian) { Array($0) } + field
        }
    }

    static func decode(_ bytes: [UInt8]) throws -> (item: ItemID, secret: [UInt8]) {
        let fields = try fields(of: bytes)

        guard let service = String(bytes: fields[0], encoding: .utf8),
            let account = String(bytes: fields[1], encoding: .utf8)
        else {
            throw HandoverError(message: "the handed-over names are not valid text")
        }

        let secret = Array(fields[2])

        guard !secret.isEmpty, secret.count <= SecretInput.maxPipedBytes else {
            throw HandoverError(message: "the handed-over secret is empty or too large")
        }

        guard let item = try? Arguments.item(service: service, account: account) else {
            throw HandoverError(message: "the handed-over names are not ones this tool stores")
        }

        return (item, secret)
    }

    private static func fields(of bytes: [UInt8]) throws -> [ArraySlice<UInt8>] {
        var fields = [ArraySlice<UInt8>]()
        var rest = bytes[...]

        while fields.count < fieldCount, rest.count >= lengthSize {
            let length = rest.prefix(lengthSize).reduce(0) { $0 << 8 | Int($1) }
            let body = rest.dropFirst(lengthSize)

            guard length <= body.count else {
                break
            }

            fields.append(body.prefix(length))
            rest = body.dropFirst(length)
        }

        guard fields.count == fieldCount, rest.isEmpty else {
            throw HandoverError(message: "the handed-over record is malformed")
        }

        return fields
    }
}

/// The build that is about to replace this one.
protocol Successor {
    /// Throws unless the successor is in place and can be changed by root only.
    func verify() throws
    /// Has the successor create the item, so that the Keychain trusts the successor, and only it, to read it.
    func store(_ secret: [UInt8], as item: ItemID) throws
}

/// Moves every secret to the build that is about to replace this one, while this build is still the one
/// the Keychain trusts. Either all of them move or none does. See docs/installation.md#updating.
struct Handover {
    private static let attempts = 3

    /// Fails instead of asking the user, so a secret this build may not read is left alone, not prompted for.
    let store: any SecretStore
    let authenticator: any Authenticator
    let requester: Requester
    let successor: any Successor
    let output: Output

    func run() async throws {
        let items = try store.list(service: nil)

        guard !items.isEmpty else {
            output.note("no secrets to hand over")

            return
        }

        try successor.verify()

        // A locked keychain refuses a read exactly as it refuses an untrusted program. Without this check
        // every secret would be skipped as not trusted, and the update would go on without them.
        guard try !store.isLocked() else {
            throw HandoverError(message: "the keychain is locked; unlock it and run the update again")
        }

        try await authenticator.authenticate(
            reason: PromptText.handoverReason(count: items.count, requester: requester)
        )

        let left = try handOver(items)
        output.note("handed over \(items.count - left.count) of \(items.count) secrets to the new build")

        if !left.isEmpty {
            output.note(
                "not handed over, because this build is not trusted to read them or their names "
                    + "are not ones it stores: \(left.map(DisplayText.described).joined(separator: ", "))")
        }
    }

    /// - Returns: the items that were left as they are.
    private func handOver(_ items: [ItemID]) throws -> [ItemID] {
        var handed = [(item: ItemID, secret: [UInt8])]()
        var left = [ItemID]()

        for item in items {
            do {
                guard let secret = try secretToHandOver(item) else {
                    left.append(item)

                    continue
                }

                // Recorded before the move: a failed move has already removed the item, so it is taken back too.
                handed.append((item, secret))
                try move(secret, as: item)
            } catch {
                throw failure(error, afterTakingBack: handed)
            }
        }

        return left
    }

    private func secretToHandOver(_ item: ItemID) throws -> [UInt8]? {
        // The marker can be put on any item by anyone; only names this tool accepts are passed on.
        guard (try? Arguments.item(service: item.service, account: item.account)) != nil else {
            return nil
        }

        do {
            return try store.read(item)
        } catch StoreError.accessDenied {
            return nil
        }
    }

    private func move(_ secret: [UInt8], as item: ItemID) throws {
        // The successor can only create the item once this one is gone: service and account identify an item.
        try store.delete(item)

        // The successor creates the item and refuses if anything is in its place. Between the removal and
        // that moment another process may have put an item there, hoping to receive the secret; such an item
        // is removed and the successor is asked again.
        for attempt in 1...Self.attempts {
            do {
                return try successor.store(secret, as: item)
            } catch _ where attempt < Self.attempts {
                try store.removeAny(item)
            }
        }
    }

    /// Returns every secret in `handed` to this build, so that a stopped update leaves things as they were.
    private func failure(_ error: any Error, afterTakingBack handed: [(item: ItemID, secret: [UInt8])]) -> any Error {
        let stranded = handed.filter { !takeBack($0.secret, as: $0.item) }.map(\.item)

        guard !stranded.isEmpty else {
            // Only this process knows what became of the secrets, so it says so itself.
            if !handed.isEmpty {
                output.note("the hand-over was undone; every secret is back with this build")
            }

            return error
        }

        // `Failure` puts its prefix on a `HandoverError`, and will put it on the one returned here.
        let reason = (error as? HandoverError)?.message ?? Failure(error).message

        return HandoverError(
            message: "\(reason); could not be taken back: "
                + stranded.map(DisplayText.described).joined(separator: ", ")
                + "; store them again with set")
    }

    /// Creates the item again under this build, in place of what the successor created.
    private func takeBack(_ secret: [UInt8], as item: ItemID) -> Bool {
        (try? store.replace(item, with: secret)) != nil
    }
}

/// The new build at the fixed place where `make update` puts it before replacing the installed one.
struct InstalledSuccessor: Successor {
    static let defaultPath = "/usr/local/bin/keytap.new"

    let path: String
    let requiredOwner: uid_t

    init(path: String = defaultPath, requiredOwner: uid_t = 0) {
        self.path = path
        self.requiredOwner = requiredOwner
    }

    /// Only root can put a program at a root-owned path in a root-owned directory, so secrets can only ever
    /// be handed to a build that root installed.
    func verify() throws {
        try verify(path, type: S_IFREG, description: "the new build \(path)")
        try verify(
            URL(fileURLWithPath: path).deletingLastPathComponent().path,
            type: S_IFDIR,
            description: "the directory of the new build"
        )
    }

    func store(_ secret: [UInt8], as item: ItemID) throws {
        guard try run(["receive"], input: HandoverRecord.encode(secret, for: item)) else {
            throw HandoverError(message: "the new build could not store \(DisplayText.described(item))")
        }
    }

    private func verify(_ path: String, type: mode_t, description: String) throws {
        var info = stat()

        guard lstat(path, &info) == 0 else {
            throw HandoverError(message: "\(description) is missing")
        }

        switch RootOwned.problem(owner: info.st_uid, mode: info.st_mode, type: type, requiredOwner: requiredOwner) {
        case .wrongType:
            let kind = type == S_IFDIR ? "a directory" : "a regular file"

            throw HandoverError(message: "\(description) is not \(kind)")
        case .wrongOwner, .writableByOthers:
            throw HandoverError(
                message: "\(description) must be owned by user id \(requiredOwner) "
                    + "and not writable by group or others")
        case nil:
            return
        }
    }

    /// - Returns: whether the successor ran and reported success.
    private func run(_ arguments: [String], input: [UInt8]) throws -> Bool {
        // If the successor exits without reading its input, the write must fail as an error rather than
        // end this process between removing a secret and taking it back.
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = [:]
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw HandoverError(message: "the new build could not be started: \(error.localizedDescription)")
        }

        // A failed write means the successor has gone; its exit status below says so.
        try? pipe.fileHandleForWriting.write(contentsOf: Data(input))
        try? pipe.fileHandleForWriting.close()
        process.waitUntilExit()

        return process.terminationReason == .exit && process.terminationStatus == 0
    }
}
