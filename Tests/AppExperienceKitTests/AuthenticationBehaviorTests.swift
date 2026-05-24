import Foundation
import Testing

@testable import AppExperienceKit

@MainActor
struct AuthenticationBehaviorTests {
    @Test
    func appIdentityStoreStartsAnonymousAndStoresGitHubMetadataLocally() throws {
        let defaults = try Self.defaults()
        let store = AppIdentityStore(defaults: defaults)
        let linkedAt = Date(timeIntervalSince1970: 100)

        #expect(store.authState == .anonymous)
        #expect(!store.isAppLockEnabled)
        #expect(store.linkedGitHubIdentity == nil)

        store.linkGitHubUser(id: 8752215, login: "daveboster", linkedAt: linkedAt)

        #expect(store.authState == .githubLinked)
        #expect(store.linkedGitHubIdentity?.id == 8752215)
        #expect(store.linkedGitHubIdentity?.login == "daveboster")
        #expect(store.linkedGitHubIdentity?.linkedAt == linkedAt)
        #expect(store.linkedGitHubIdentity?.isCredentialStale == false)
    }

    @Test
    func appIdentityStoreDisconnectsGitHubWithoutChangingAppLock() throws {
        let defaults = try Self.defaults()
        let store = AppIdentityStore(defaults: defaults)
        store.setAppLockEnabled(true)
        store.linkGitHubUser(id: 8752215, login: "daveboster", linkedAt: Date(timeIntervalSince1970: 100))

        store.disconnectGitHub()

        #expect(store.authState == .anonymous)
        #expect(store.linkedGitHubIdentity == nil)
        #expect(store.isAppLockEnabled)
    }

    @Test
    func appIdentityStoreMarksGitHubCredentialStale() throws {
        let defaults = try Self.defaults()
        let store = AppIdentityStore(defaults: defaults)
        store.linkGitHubUser(id: 8752215, login: "daveboster", linkedAt: Date(timeIntervalSince1970: 100))

        store.markGitHubCredentialStale()

        #expect(store.linkedGitHubIdentity?.isCredentialStale == true)
    }

    @Test
    func appLockControllerSkipsAuthenticationWhenFeatureInactiveOrAppLockOff() async throws {
        let defaults = try Self.defaults()
        let store = AppIdentityStore(defaults: defaults)
        let authenticator = FakeLocalAuthenticator(outcome: .success)
        let controller = AppLockController(identityStore: store, authenticator: authenticator)
        let decision = ReleaseControlDecision(
            key: .authenticationFeature,
            isEnabled: true,
            variables: ["app_lock_available": "true"]
        )

        let inactive = await controller.evaluateLaunchAccess(decision: decision, preference: .systemDefault)
        let lockOff = await controller.evaluateLaunchAccess(decision: decision, preference: .optIn)

        #expect(inactive == .unlocked)
        #expect(lockOff == .unlocked)
        #expect(await authenticator.callCount == 0)
    }

    @Test
    func appLockControllerAuthenticatesWhenLaunchOnlyLockIsEnabled() async throws {
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

        let state = await controller.evaluateLaunchAccess(decision: decision, preference: .optIn)

        #expect(state == .unlocked)
        #expect(await authenticator.callCount == 1)
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
    func appLockControllerKeepsContentLockedWhenAuthenticationFails() async throws {
        let defaults = try Self.defaults()
        let store = AppIdentityStore(defaults: defaults)
        store.setAppLockEnabled(true)
        let authenticator = FakeLocalAuthenticator(outcome: .canceled)
        let controller = AppLockController(identityStore: store, authenticator: authenticator)
        let decision = ReleaseControlDecision(
            key: .authenticationFeature,
            isEnabled: true,
            variables: ["app_lock_available": "true"]
        )

        let state = await controller.evaluateLaunchAccess(decision: decision, preference: .optIn)

        #expect(state == .locked(reason: "Authentication was canceled."))
    }

    @Test
    func appLaunchSessionRefreshesAndAuthenticatesOnlyOnceAcrossWindows() async throws {
        let defaults = try Self.defaults()
        let identityStore = AppIdentityStore(defaults: defaults)
        identityStore.setAppLockEnabled(true)
        let preferenceStore = ReleaseControlPreferenceStore(defaults: defaults)
        preferenceStore.setPreference(.optIn, for: .authenticationFeature)
        let authenticator = FakeLocalAuthenticator(outcome: .success)
        let client = AuthenticationReleaseControlClient(
            decision: ReleaseControlDecision(
                key: .authenticationFeature,
                isEnabled: true,
                variables: [
                    "app_lock_available": "true",
                    "app_lock_mode": "launch_only",
                    "flag_type": "app_launch",
                    "flag_control_type": "opt_in"
                ]
            )
        )
        let session = AppLaunchSession(
            releaseControlClient: client,
            preferenceStore: preferenceStore,
            identityStore: identityStore,
            authenticator: authenticator
        )

        #expect(session.releaseControlPreparationID == 0)
        await session.prepareIfNeeded()
        #expect(session.releaseControlPreparationID == 1)
        await session.prepareIfNeeded()

        #expect(session.accessState == .unlocked)
        #expect(session.releaseControlPreparationID == 1)
        #expect(await client.refreshCount == 1)
        #expect(await client.decisionKeys == [.authenticationFeature])
        #expect(await authenticator.callCount == 1)
    }

    @Test
    func appLaunchSessionSkipsAuthenticationWhenFlagIsNotAppLaunch() async throws {
        let defaults = try Self.defaults()
        let identityStore = AppIdentityStore(defaults: defaults)
        identityStore.setAppLockEnabled(true)
        let preferenceStore = ReleaseControlPreferenceStore(defaults: defaults)
        preferenceStore.setPreference(.optIn, for: .authenticationFeature)
        let authenticator = FakeLocalAuthenticator(outcome: .success)
        let client = AuthenticationReleaseControlClient(
            decision: ReleaseControlDecision(
                key: .authenticationFeature,
                isEnabled: true,
                variables: [
                    "app_lock_available": "true",
                    "app_lock_mode": "launch_only",
                    "flag_type": "extension_launch",
                    "flag_control_type": "opt_in"
                ]
            )
        )
        let session = AppLaunchSession(
            releaseControlClient: client,
            preferenceStore: preferenceStore,
            identityStore: identityStore,
            authenticator: authenticator
        )

        await session.prepareIfNeeded()

        #expect(session.accessState == .unlocked)
        #expect(await client.refreshCount == 1)
        #expect(await authenticator.callCount == 0)
    }

    @Test
    func githubIdentityClientFetchesAuthenticatedUserMetadata() async throws {
        let session = AuthenticationRecordingHTTPClient(
            responseData: Data(#"{"id":8752215,"login":"daveboster"}"#.utf8),
            statusCode: 200
        )
        let client = GitHubRESTIdentityClient(httpClient: session)

        let identity = try await client.fetchAuthenticatedUser(token: "github-token")

        #expect(identity.id == 8752215)
        #expect(identity.login == "daveboster")
        #expect(session.lastRequest?.url?.absoluteString == "https://api.github.com/user")
        #expect(session.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer github-token")
        #expect(session.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    }

    @Test
    func githubIdentityClientKeepsAuthenticationFailuresExplicit() async {
        let session = AuthenticationRecordingHTTPClient(
            responseData: Data(#"{"message":"Bad credentials"}"#.utf8),
            statusCode: 401
        )
        let client = GitHubRESTIdentityClient(httpClient: session)

        await #expect(throws: GitHubIdentityClientError.authenticationRequired) {
            _ = try await client.fetchAuthenticatedUser(token: "expired")
        }
    }

    private static func defaults() throws -> UserDefaults {
        let suiteName = "AuthenticationBehaviorTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
    }
}

private actor AuthenticationReleaseControlClient: ReleaseControlClient {
    private let storedDecision: ReleaseControlDecision
    private var storedRefreshCount = 0
    private var storedDecisionKeys: [ReleaseControlKey] = []
    private var events: [ReleaseControlEvent] = []

    init(decision: ReleaseControlDecision) {
        self.storedDecision = decision
    }

    var refreshCount: Int {
        storedRefreshCount
    }

    var decisionKeys: [ReleaseControlKey] {
        storedDecisionKeys
    }

    var trackedEvents: [ReleaseControlEvent] {
        events
    }

    func status() async -> ReleaseControlStatus {
        ReleaseControlStatus(
            provider: .optimizely,
            connectionState: .connected,
            environmentKey: "development",
            userId: "anonymous-install",
            datafileURL: URL(string: "https://cdn.optimizely.com/datafiles/test.json")
        )
    }

    func refresh() async {
        storedRefreshCount += 1
    }

    func decision(for key: ReleaseControlKey) async -> ReleaseControlDecision {
        storedDecisionKeys.append(key)
        guard key == storedDecision.key else {
            return .disabled(key, reason: "No fake decision configured")
        }

        return storedDecision
    }

    func track(_ event: ReleaseControlEvent) async {
        events.append(event)
    }
}

private actor FakeLocalAuthenticator: LocalAuthenticating {
    private let outcome: LocalAuthenticationOutcome
    private var storedCallCount = 0
    private var storedLastReason: String?

    init(outcome: LocalAuthenticationOutcome) {
        self.outcome = outcome
    }

    var callCount: Int {
        storedCallCount
    }

    var lastReason: String? {
        storedLastReason
    }

    func authenticate(reason: String) async -> LocalAuthenticationOutcome {
        storedCallCount += 1
        storedLastReason = reason
        return outcome
    }
}

private final class AuthenticationRecordingHTTPClient: HTTPClient {
    private let responseData: Data
    private let statusCode: Int

    private(set) var lastRequest: URLRequest?

    init(responseData: Data, statusCode: Int) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}
