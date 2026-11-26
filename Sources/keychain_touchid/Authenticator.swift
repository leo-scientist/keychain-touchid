import LocalAuthentication

struct AuthenticationError: Error, Equatable {
    let message: String
}

protocol Authenticator {
    func authenticate(reason: String) async throws
}

/// See docs/authentication.md.
struct LocalAuthenticator: Authenticator {
    let policy: LAPolicy

    func authenticate(reason: String) async throws {
        let context = LAContext()
        // The user is refusing a request made by another program, not cancelling an action of their own.
        context.localizedCancelTitle = "Deny"
        let isConfirmed: Bool

        do {
            isConfirmed = try await context.evaluatePolicy(policy, localizedReason: reason)
        } catch {
            throw AuthenticationError(message: error.localizedDescription)
        }

        guard isConfirmed else {
            throw AuthenticationError(message: "not confirmed")
        }
    }
}

extension AuthPolicy {
    var localAuthenticationPolicy: LAPolicy {
        switch self {
        case .any:
            .deviceOwnerAuthentication
        case .biometry:
            .deviceOwnerAuthenticationWithBiometrics
        }
    }
}
