import Foundation

enum InputError: Error, Equatable {
    case empty
    case tooLarge
    case tooLongForTerminal
    case unreadable(String)
}

/// See docs/commands.md#entering-a-secret.
enum SecretInput {
    static let maxPipedBytes = 64 * 1024
    /// A terminal line stops at MAX_CANON bytes, so an entry this long may already be truncated.
    static let maxTerminalBytes = Int(MAX_CANON) - 1
    private static let terminalBufferSize = 4 * Int(MAX_CANON)

    static func read(for item: ItemID) throws -> [UInt8] {
        guard isatty(STDIN_FILENO) == 1 else {
            return try normalized(readAll(from: .standardInput))
        }

        return try readHidden(prompt: "Secret for “\(item.service)” (\(item.account)): ")
    }

    /// Stops one byte past the largest acceptable input, which is enough to tell it was exceeded.
    static func readAll(from handle: FileHandle) throws -> [UInt8] {
        let limit = maxPipedBytes + "\r\n".utf8.count + 1
        var bytes = [UInt8]()

        while bytes.count < limit {
            let chunk: Data?

            do {
                chunk = try handle.read(upToCount: limit - bytes.count)
            } catch {
                throw InputError.unreadable(error.localizedDescription)
            }

            guard let chunk, !chunk.isEmpty else {
                break
            }

            bytes.append(contentsOf: chunk)
        }

        return bytes
    }

    static func normalized(_ input: [UInt8]) throws -> [UInt8] {
        let secret = strippingLineEnding(input)

        guard !secret.isEmpty else {
            throw InputError.empty
        }

        guard secret.count <= maxPipedBytes else {
            throw InputError.tooLarge
        }

        return secret
    }

    /// `readpassphrase` turns echo off and restores the terminal itself, also when interrupted by a signal.
    private static func readHidden(prompt: String) throws -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: terminalBufferSize)

        guard readpassphrase(prompt, &buffer, buffer.count, RPP_ECHO_OFF | RPP_REQUIRE_TTY) != nil else {
            throw InputError.unreadable(String(cString: strerror(errno)))
        }

        let secret = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }

        guard !secret.isEmpty else {
            throw InputError.empty
        }

        guard secret.count < maxTerminalBytes else {
            throw InputError.tooLongForTerminal
        }

        return secret
    }

    private static func strippingLineEnding(_ bytes: [UInt8]) -> [UInt8] {
        guard bytes.last == UInt8(ascii: "\n") else {
            return bytes
        }

        let line = bytes.dropLast()

        return Array(line.last == UInt8(ascii: "\r") ? line.dropLast() : line)
    }
}
