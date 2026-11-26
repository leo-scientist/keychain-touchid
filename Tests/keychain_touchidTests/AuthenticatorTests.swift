import LocalAuthentication
import Testing
@testable import keychain_touchid

@Suite struct AuthenticatorTests {
    @Test func policySettingSelectsTheAuthenticationStrength() {
        #expect(AuthPolicy.any.localAuthenticationPolicy == .deviceOwnerAuthentication)
        #expect(AuthPolicy.biometry.localAuthenticationPolicy == .deviceOwnerAuthenticationWithBiometrics)
    }
}
