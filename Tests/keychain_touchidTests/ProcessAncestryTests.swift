import Darwin
import Testing
@testable import keychain_touchid

@Suite struct ProcessAncestryTests {
    @Test func describesProcessesOfOtherUsers() {
        // launchd belongs to root, like the `login` process that leads a Terminal tab's session.
        #expect(ProcessAncestry.info(of: 1) != nil)
        #expect(ProcessAncestry.info(of: getpid()) != nil)
        #expect(ProcessAncestry.info(of: .max) == nil)
    }

    @Test func chainStartsAtTheGivenProcessAndStopsBeforeLaunchd() throws {
        let chain = ProcessAncestry.chain(from: getpid())
        let own = try #require(chain.first)

        #expect(own.executablePath?.hasPrefix("/") == true)
        #expect(!own.name.isEmpty)
        #expect(chain.count > 1)
        #expect(ProcessAncestry.chain(from: 1).isEmpty)
        #expect(ProcessAncestry.chain(from: .max).isEmpty)
    }

    @Test func readsTheArgumentsOfAProcessOfTheSameUser() {
        let own = ProcessAncestry.arguments(of: getpid())

        #expect(own == CommandLine.arguments)
    }

    @Test func argumentsOfAnotherUsersProcessAreNotDisclosed() {
        #expect(ProcessAncestry.arguments(of: 1).isEmpty)
        #expect(ProcessAncestry.arguments(of: .max).isEmpty)
    }
}
