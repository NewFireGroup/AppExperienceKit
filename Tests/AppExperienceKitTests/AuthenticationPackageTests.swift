import Foundation
import Testing

@testable import AppExperienceKit

@MainActor
struct AuthenticationPackageTests {
    @Test
    func appExperienceHostConfigurationBuildsGenericHostCopy() {
        let configuration = AppExperienceHostConfiguration(productName: "Budget Studio")

        #expect(configuration.productName == "Budget Studio")
        #expect(configuration.displayName == "Budget Studio")
        #expect(configuration.loadingTitle == "Loading Budget Studio...")
        #expect(configuration.lockedTitle == "Budget Studio Locked")
        #expect(configuration.localAuthenticationReason == "Unlock Budget Studio.")
    }

    @Test
    func appLockControllerUsesHostProvidedAuthenticationReason() async throws {
        let defaults = try Self.defaults()
        let store = AppIdentityStore(defaults: defaults)
        store.setAppLockEnabled(true)
        let authenticator = FakeLocalAuthenticator(outcome: .success)
        let controller = AppLockController(identityStore: store, authenticator: authenticator)
        let decision = ReleaseControlDecision(
            key: .authenticationFeature,
            isEnabled: true,
            variables: [
                "app_lock_available": "true",
                "app_lock_mode": "launch_only"
            ]
        )

        let state = await controller.evaluateLaunchAccess(
            decision: decision,
            preference: .optIn,
            reason: "Unlock Budget Studio."
        )

        #expect(state == .unlocked)
        #expect(await authenticator.lastReason == "Unlock Budget Studio.")
    }

    private static func defaults() throws -> UserDefaults {
        let suiteName = "AuthenticationPackageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private actor FakeLocalAuthenticator: LocalAuthenticating {
    private let outcome: LocalAuthenticationOutcome
    private var storedLastReason: String?

    init(outcome: LocalAuthenticationOutcome) {
        self.outcome = outcome
    }

    var lastReason: String? {
        storedLastReason
    }

    func authenticate(reason: String) async -> LocalAuthenticationOutcome {
        storedLastReason = reason
        return outcome
    }
}
