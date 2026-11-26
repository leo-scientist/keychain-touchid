import Foundation
import Testing
@testable import keychain_touchid

@Suite struct SettingsTests {
    private static let regularFile: mode_t = S_IFREG

    // MARK: parse

    @Test(arguments: ["", "\n\n", "# only a comment\n", "   \n#cache_seconds = 60\n"])
    func nothingSetMeansDefaults(text: String) throws {
        #expect(try Settings.parse(text) == Settings(cacheSeconds: 0, policy: .any))
    }

    @Test func readsBothSettings() throws {
        let text = """
            # reuse for five minutes
            cache_seconds = 300
            policy=biometry   # Touch ID only
            """

        #expect(try Settings.parse(text) == Settings(cacheSeconds: 300, policy: .biometry))
    }

    @Test func readsWindowsLineEndings() throws {
        let text = "# header\r\ncache_seconds = 300\r\npolicy = biometry\r\n"

        #expect(try Settings.parse(text) == Settings(cacheSeconds: 300, policy: .biometry))

        #expect(throws: SettingsError(message: "line 2: unknown setting")) {
            try Settings.parse("# header\r\ncolour = blue\r\n")
        }
    }

    @Test func acceptsTheBoundsOfTheCacheWindow() throws {
        #expect(try Settings.parse("cache_seconds = 0").cacheSeconds == 0)
        #expect(try Settings.parse("cache_seconds = 86400").cacheSeconds == 86_400)
        #expect(try Settings.parse("policy = any").policy == .any)
    }

    @Test(arguments: [
        "cache_seconds = 86401",
        "cache_seconds = -1",
        "cache_seconds = 1.5",
        "cache_seconds = ten",
        "cache_seconds =",
        "policy = Any",
        "policy = password",
        "policy",
        "timeout = 5",
        "cache_seconds = 10\ncache_seconds = 20",
        "= 5",
    ])
    func rejectsInvalidContent(text: String) {
        #expect(throws: SettingsError.self) {
            try Settings.parse(text)
        }
    }

    @Test func errorNamesTheLine() {
        #expect(throws: SettingsError(message: "line 3: unknown setting")) {
            try Settings.parse("# header\n\ncolour = blue\n")
        }
    }

    // MARK: trust

    @Test func trustsARootOwnedFileOthersCannotWrite() throws {
        try Settings.checkTrust(owner: 0, mode: Self.regularFile | 0o644)
        try Settings.checkTrust(owner: 0, mode: Self.regularFile | 0o600)
        try Settings.checkTrust(owner: 0, mode: Self.regularFile | 0o444)
    }

    @Test(arguments: [
        (uid_t(501), SettingsTests.regularFile | 0o644),
        (uid_t(0), SettingsTests.regularFile | 0o664),
        (uid_t(0), SettingsTests.regularFile | 0o646),
        (uid_t(0), SettingsTests.regularFile | 0o666),
        (uid_t(0), mode_t(S_IFDIR) | 0o755),
        (uid_t(0), mode_t(S_IFIFO) | 0o644),
    ])
    func distrustsEverythingElse(owner: uid_t, mode: mode_t) {
        #expect(throws: SettingsError.self) {
            try Settings.checkTrust(owner: owner, mode: mode)
        }
    }

    // MARK: load

    @Test func missingFileMeansDefaults() throws {
        #expect(try Settings.load(from: temporaryPath()) == .defaults)
    }

    @Test func loadsAFileOwnedByTheRequiredUser() throws {
        let path = try writeSettings("cache_seconds = 120\n", permissions: 0o644)

        defer {
            try? FileManager.default.removeItem(atPath: path)
        }

        #expect(try Settings.load(from: path, requiredOwner: getuid()).cacheSeconds == 120)
    }

    @Test func emptyFileMeansDefaults() throws {
        let path = try writeSettings("", permissions: 0o644)

        defer {
            try? FileManager.default.removeItem(atPath: path)
        }

        #expect(try Settings.load(from: path, requiredOwner: getuid()) == .defaults)
    }

    @Test func refusesAnOversizedFile() throws {
        let path = try writeSettings(String(repeating: "# padding\n", count: 10_000), permissions: 0o644)

        defer {
            try? FileManager.default.removeItem(atPath: path)
        }

        #expect(throws: SettingsError.self) {
            try Settings.load(from: path, requiredOwner: getuid())
        }
    }

    @Test func refusesAFileOwnedBySomeoneElse() throws {
        let path = try writeSettings("cache_seconds = 120\n", permissions: 0o644)

        defer {
            try? FileManager.default.removeItem(atPath: path)
        }

        #expect(throws: SettingsError.self) {
            try Settings.load(from: path, requiredOwner: getuid() + 1)
        }
    }

    @Test func refusesAFileOthersCanWrite() throws {
        let path = try writeSettings("cache_seconds = 120\n", permissions: 0o666)

        defer {
            try? FileManager.default.removeItem(atPath: path)
        }

        #expect(throws: SettingsError.self) {
            try Settings.load(from: path, requiredOwner: getuid())
        }
    }

    @Test func refusesASymbolicLink() throws {
        let target = try writeSettings("cache_seconds = 120\n", permissions: 0o644)
        let link = temporaryPath()
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)

        defer {
            try? FileManager.default.removeItem(atPath: link)
            try? FileManager.default.removeItem(atPath: target)
        }

        #expect(throws: SettingsError.self) {
            try Settings.load(from: link, requiredOwner: getuid())
        }
    }

    @Test func refusesInvalidContentInsteadOfFallingBack() throws {
        let path = try writeSettings("cache_seconds = forever\n", permissions: 0o644)

        defer {
            try? FileManager.default.removeItem(atPath: path)
        }

        #expect(throws: SettingsError.self) {
            try Settings.load(from: path, requiredOwner: getuid())
        }
    }

    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("keychain-touchid-test-\(UUID().uuidString).conf").path
    }

    private func writeSettings(_ text: String, permissions: Int) throws -> String {
        let path = temporaryPath()
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)

        return path
    }
}
