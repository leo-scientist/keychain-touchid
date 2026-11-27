import Darwin
import Testing
@testable import keychain_touchid

@Suite struct RootOwnedTests {
    @Test func acceptsWhatOnlyTheOwnerCanChange() {
        #expect(RootOwned.problem(owner: 0, mode: S_IFREG | 0o755, type: S_IFREG) == nil)
        #expect(RootOwned.problem(owner: 0, mode: S_IFDIR | 0o755, type: S_IFDIR) == nil)
        #expect(RootOwned.problem(owner: 501, mode: S_IFREG | 0o600, type: S_IFREG, requiredOwner: 501) == nil)
    }

    @Test func reportsWhatIsWrong() {
        #expect(RootOwned.problem(owner: 0, mode: S_IFLNK | 0o755, type: S_IFREG) == .wrongType)
        #expect(RootOwned.problem(owner: 0, mode: S_IFREG | 0o755, type: S_IFDIR) == .wrongType)
        #expect(RootOwned.problem(owner: 501, mode: S_IFREG | 0o755, type: S_IFREG) == .wrongOwner)
        #expect(RootOwned.problem(owner: 0, mode: S_IFREG | 0o775, type: S_IFREG) == .writableByOthers)
        #expect(RootOwned.problem(owner: 0, mode: S_IFDIR | 0o757, type: S_IFDIR) == .writableByOthers)
    }
}
