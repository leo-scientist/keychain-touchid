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
        let isConfirmed: Bool

        do {
            isConfirmed = try await LAContext().evaluatePolicy(policy, localizedReason: reason)
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
