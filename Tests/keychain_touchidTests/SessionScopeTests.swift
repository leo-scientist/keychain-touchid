import Foundation
import Testing
@testable import keychain_touchid

@Suite struct SessionScopeTests {
    @Test func processWithoutAControllingTerminalHasNoScope() {
        #expect(SessionScope(sessionID: 100, leaderStartedAt: 1_000, terminal: SessionScope.noTerminal) == nil)
    }

    @Test func scopeDiffersBySessionStartTimeAndTerminal() throws {
        let scope = try #require(SessionScope(sessionID: 100, leaderStartedAt: 1_000, terminal: 7))

        #expect(scope == SessionScope(sessionID: 100, leaderStartedAt: 1_000, terminal: 7))
        #expect(scope != SessionScope(sessionID: 101, leaderStartedAt: 1_000, terminal: 7))
        #expect(scope != SessionScope(sessionID: 100, leaderStartedAt: 1_001, terminal: 7))
        #expect(scope != SessionScope(sessionID: 100, leaderStartedAt: 1_000, terminal: 8))
    }

    @Test func currentScopeIsStableWithinAProcess() {
        #expect(SessionScope.current() == SessionScope.current())
    }

    @Test func currentScopeExistsExactlyWhenThereIsAControllingTerminal() {
        let descriptor = open("/dev/tty", O_RDONLY | O_NOCTTY)
        let hasControllingTerminal = descriptor >= 0

        if hasControllingTerminal {
            close(descriptor)
        }

        #expect((SessionScope.current() != nil) == hasControllingTerminal)
    }

    @Test func describesProcessesOfOtherUsers() {
        // launchd belongs to root, like the `login` process that leads a Terminal tab's session.
        #expect(SessionScope.processInfo(of: 1) != nil)
        #expect(SessionScope.processInfo(of: getpid()) != nil)
        #expect(SessionScope.processInfo(of: .max) == nil)
    }

    @Test func survivesEncoding() throws {
        let scope = try #require(SessionScope(sessionID: 100, leaderStartedAt: 1_000, terminal: 7))
        let decoded = try JSONDecoder().decode(SessionScope.self, from: JSONEncoder().encode(scope))

        #expect(decoded == scope)
    }
}
