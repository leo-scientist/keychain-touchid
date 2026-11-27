import Foundation
import Security

enum ExitCode: Int32 {
    case success = 0
    case failure = 1
    case usage = 2
    case authentication = 3
    case notFound = 4
}

/// What the user is told, and the exit code a script sees, for an error from any layer.
/// See docs/commands.md#exit-codes.
struct Failure: Equatable {
    let code: ExitCode
    let message: String

    init(code: ExitCode, message: String) {
        self.code = code
        self.message = message
    }

    init(_ error: any Error) {
        switch error {
        case let error as UsageError:
            self.init(code: .usage, message: error.message)
        case let error as InputError:
            self = Self.describing(error)
        case let error as StoreError:
            self = Self.describing(error)
        case let error as AuthenticationError:
            self.init(code: .authentication, message: "authentication failed: \(error.message)")
        case let error as SettingsError:
            self.init(code: .failure, message: "settings: \(error.message)")
        case let error as HandoverError:
            self.init(code: .failure, message: "hand-over: \(error.message)")
        default:
            self.init(code: .failure, message: error.localizedDescription)
        }
    }

    private static func describing(_ error: InputError) -> Failure {
        switch error {
        case .empty:
            Failure(code: .usage, message: "the secret is empty")
        case .tooLarge:
            Failure(code: .usage, message: "the secret is larger than \(SecretInput.maxPipedBytes) bytes")
        case .tooLongForTerminal:
            Failure(
                code: .usage,
                message: "the secret is too long to type or paste at the prompt; pipe it instead, "
                    + "for example: pbpaste | keytap set <service> <account>"
            )
        case let .unreadable(reason):
            Failure(code: .failure, message: "cannot read the secret: \(reason)")
        }
    }

    private static func describing(_ error: StoreError) -> Failure {
        switch error {
        case .notFound:
            Failure(code: .notFound, message: "no such item, or it was not created by keytap")
        case .duplicateItem:
            Failure(
                code: .failure,
                message: "an item with this service and account exists but was not created by keytap; "
                    + "remove it first (security delete-generic-password -s <service> -a <account>) "
                    + "or choose another name"
            )
        case .accessDenied:
            Failure(code: .authentication, message: "the Keychain denied access to the item")
        case .locked:
            Failure(code: .failure, message: "the keychain is locked; unlock it and try again")
        case let .unexpected(status):
            Failure(code: .failure, message: "Keychain error \(status): \(keychainMessage(for: status))")
        }
    }

    private static func keychainMessage(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
    }
}
