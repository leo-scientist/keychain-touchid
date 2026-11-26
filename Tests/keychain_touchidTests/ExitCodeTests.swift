import Foundation
import Security
import Testing
@testable import keychain_touchid

@Suite struct ExitCodeTests {
    @Test func codesAreStable() {
        #expect(ExitCode.success.rawValue == 0)
        #expect(ExitCode.failure.rawValue == 1)
        #expect(ExitCode.usage.rawValue == 2)
        #expect(ExitCode.authentication.rawValue == 3)
        #expect(ExitCode.notFound.rawValue == 4)
    }

    @Test func everyErrorMapsToItsCode() {
        let expectations: [(any Error, ExitCode)] = [
            (UsageError(message: "missing command"), .usage),
            (InputError.empty, .usage),
            (InputError.tooLarge, .usage),
            (InputError.tooLongForTerminal, .usage),
            (InputError.unreadable("closed"), .failure),
            (StoreError.notFound, .notFound),
            (StoreError.duplicateItem, .failure),
            (StoreError.accessDenied, .authentication),
            (StoreError.unexpected(errSecIO), .failure),
            (AuthenticationError(message: "cancelled"), .authentication),
            (SettingsError(message: "line 1: unknown setting"), .failure),
            (CocoaError(.fileReadUnknown), .failure),
        ]

        for (error, code) in expectations {
            let failure = Failure(error)

            #expect(failure.code == code, "\(error)")
            #expect(!failure.message.isEmpty, "\(error)")
        }
    }

    @Test func messagesCarryTheDetail() {
        #expect(Failure(UsageError(message: "missing command")).message == "missing command")
        #expect(Failure(AuthenticationError(message: "cancelled")).message.hasSuffix("cancelled"))
        #expect(Failure(SettingsError(message: "line 3: oops")).message.hasSuffix("line 3: oops"))
        #expect(Failure(StoreError.unexpected(errSecIO)).message.contains("\(errSecIO)"))
        #expect(Failure(StoreError.duplicateItem).message.contains("security delete-generic-password"))
    }
}
