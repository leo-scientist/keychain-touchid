import Foundation
import Testing
@testable import keychain_touchid

@Suite struct SecretInputTests {
    @Test func stripsOneTrailingLineEnding() throws {
        #expect(try SecretInput.normalized(bytes("token\n")) == bytes("token"))
        #expect(try SecretInput.normalized(bytes("token\r\n")) == bytes("token"))
        #expect(try SecretInput.normalized(bytes("token")) == bytes("token"))
    }

    @Test func keepsEverythingElse() throws {
        #expect(try SecretInput.normalized(bytes("token\n\n")) == bytes("token\n"))
        #expect(try SecretInput.normalized(bytes("line 1\nline 2\n")) == bytes("line 1\nline 2"))
        #expect(try SecretInput.normalized(bytes(" token \r")) == bytes(" token \r"))
        #expect(try SecretInput.normalized([0x00, 0xFF, 0x0A]) == [0x00, 0xFF])
    }

    @Test(arguments: ["", "\n", "\r\n"])
    func rejectsEmptySecret(input: String) {
        #expect(throws: InputError.empty) {
            try SecretInput.normalized(bytes(input))
        }
    }

    @Test func enforcesTheSizeLimit() throws {
        let largest = [UInt8](repeating: 0x61, count: SecretInput.maxPipedBytes)

        #expect(try SecretInput.normalized(largest + bytes("\r\n")) == largest)

        #expect(throws: InputError.tooLarge) {
            try SecretInput.normalized(largest + [0x61])
        }
    }

    @Test func readsPipedInputToTheEnd() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data([0x00, 0xFF, 0x0A]))
        try pipe.fileHandleForWriting.close()

        #expect(try SecretInput.readAll(from: pipe.fileHandleForReading) == [0x00, 0xFF, 0x0A])
    }

    @Test func oversizedPipedInputIsRejectedWithoutReadingItAll() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychain-touchid-test-\(UUID().uuidString).bin")
        try Data(count: 4 * SecretInput.maxPipedBytes).write(to: path)

        defer {
            try? FileManager.default.removeItem(at: path)
        }

        let input = try SecretInput.readAll(from: FileHandle(forReadingFrom: path))

        #expect(input.count < 2 * SecretInput.maxPipedBytes)

        #expect(throws: InputError.tooLarge) {
            try SecretInput.normalized(input)
        }
    }
}
