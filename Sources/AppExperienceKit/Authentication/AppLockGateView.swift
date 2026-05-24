import Combine
import SwiftUI

@MainActor
public final class AppLaunchSession: ObservableObject {
    @Published public private(set) var accessState: AppLockAccessState?
    @Published public private(set) var isPreparing = false
    @Published public private(set) var releaseControlPreparationID = 0

    private let releaseControlClient: any ReleaseControlClient
    private let readiness: ReleaseControlLaunchReadiness
    private let preferenceStore: ReleaseControlPreferenceStore
    private let identityStore: AppIdentityStore
    private let authenticator: any LocalAuthenticating
    let hostConfiguration: AppExperienceHostConfiguration
    private var didPrepareReleaseControls = false
    private var didCompleteLaunchCheck = false

    public init(
        releaseControlClient: any ReleaseControlClient,
        readiness: ReleaseControlLaunchReadiness = ReleaseControlLaunchReadiness(),
        preferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore(),
        identityStore: AppIdentityStore = AppIdentityStore(),
        authenticator: any LocalAuthenticating = SystemLocalAuthenticator(),
        hostConfiguration: AppExperienceHostConfiguration = .mainBundle()
    ) {
        self.releaseControlClient = releaseControlClient
        self.readiness = readiness
        self.preferenceStore = preferenceStore
        self.identityStore = identityStore
        self.authenticator = authenticator
        self.hostConfiguration = hostConfiguration
    }

    public func prepareIfNeeded() async {
        guard !didCompleteLaunchCheck, !isPreparing else {
            return
        }

        await runLaunchCheck(refreshReleaseControls: !didPrepareReleaseControls)
    }

    public func retryUnlock() async {
        guard !isPreparing else {
            return
        }

        await runLaunchCheck(refreshReleaseControls: !didPrepareReleaseControls)
    }

    private func runLaunchCheck(refreshReleaseControls: Bool) async {
        isPreparing = true
        accessState = nil
        defer {
            isPreparing = false
            didCompleteLaunchCheck = accessState != nil
        }

        if refreshReleaseControls {
            await readiness.prepare(using: releaseControlClient)
            didPrepareReleaseControls = true
            releaseControlPreparationID += 1
        }

        let rawDecision = await releaseControlClient.decision(for: .authenticationFeature)
        let preference = preferenceStore.preference(for: .authenticationFeature)
        guard rawDecision.flagType == .appLaunch else {
            accessState = .unlocked
            return
        }

        let decision = rawDecision.applying(preference)
        let nextState = await AppLockController(
            identityStore: identityStore,
            authenticator: authenticator
        )
        .evaluateLaunchAccess(
            decision: decision,
            preference: preference,
            reason: hostConfiguration.localAuthenticationReason
        )
        accessState = nextState

        let shouldAttemptUnlock = decision.isAuthenticationAppLockAvailable(preference: preference) &&
            decision.authenticationAppLockMode == .launchOnly &&
            identityStore.isAppLockEnabled
        guard shouldAttemptUnlock else {
            return
        }

        switch nextState {
        case .unlocked:
            await releaseControlClient.track(.authenticationAppUnlockCompleted(
                result: "success",
                lockMode: AuthenticationAppLockMode.launchOnly.rawValue,
                variationKey: decision.variationKey
            ))
        case .locked(let reason):
            await releaseControlClient.track(.authenticationAppUnlockFailed(
                result: reason == "Authentication was canceled." ? "canceled" : "failed",
                lockMode: AuthenticationAppLockMode.launchOnly.rawValue,
                variationKey: decision.variationKey
            ))
        }
    }
}

public struct AppLaunchGateView<Content: View>: View {
    @ObservedObject private var session: AppLaunchSession
    private let content: () -> Content

    public init(
        session: AppLaunchSession,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.session = session
        self.content = content
    }

    public var body: some View {
        Group {
            switch session.accessState {
            case .unlocked:
                content()
            case .locked(let reason):
                lockedView(reason: reason)
            case nil:
                VStack(spacing: 16) {
                    ProgressView()
                    Text(session.hostConfiguration.loadingTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await session.prepareIfNeeded()
        }
        .environmentObject(session)
    }

    private func lockedView(reason: String) -> some View {
        ContentUnavailableView {
            Label(session.hostConfiguration.lockedTitle, systemImage: "lock")
        } description: {
            Text(reason)
        } actions: {
            Button("Unlock") {
                Task { await session.retryUnlock() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

public struct AppLockGateView<Content: View>: View {
    @Environment(\.releaseControlClient) private var releaseControlClient

    @State private var accessState: AppLockAccessState?

    private let preferenceStore: ReleaseControlPreferenceStore
    private let identityStore: AppIdentityStore
    private let authenticator: any LocalAuthenticating
    private let hostConfiguration: AppExperienceHostConfiguration
    private let content: () -> Content

    public init(
        preferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore(),
        identityStore: AppIdentityStore = AppIdentityStore(),
        authenticator: any LocalAuthenticating = SystemLocalAuthenticator(),
        hostConfiguration: AppExperienceHostConfiguration = .mainBundle(),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.preferenceStore = preferenceStore
        self.identityStore = identityStore
        self.authenticator = authenticator
        self.hostConfiguration = hostConfiguration
        self.content = content
    }

    public var body: some View {
        Group {
            switch accessState {
            case .unlocked:
                content()
            case .locked(let reason):
                lockedView(reason: reason)
            case nil:
                ProgressView("Checking authentication...")
            }
        }
        .task {
            await evaluateAccess()
        }
    }

    private func lockedView(reason: String) -> some View {
        ContentUnavailableView {
            Label(hostConfiguration.lockedTitle, systemImage: "lock")
        } description: {
            Text(reason)
        } actions: {
            Button("Unlock") {
                Task { await evaluateAccess() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @MainActor
    private func evaluateAccess() async {
        let rawDecision = await releaseControlClient.decision(for: .authenticationFeature)
        let preference = preferenceStore.preference(for: .authenticationFeature)
        guard rawDecision.flagType == .appLaunch else {
            accessState = .unlocked
            return
        }

        let decision = rawDecision.applying(preference)
        let shouldAttemptUnlock = decision.isAuthenticationAppLockAvailable(preference: preference) &&
            decision.authenticationAppLockMode == .launchOnly &&
            identityStore.isAppLockEnabled
        let controller = AppLockController(identityStore: identityStore, authenticator: authenticator)
        let nextState = await controller.evaluateLaunchAccess(
            decision: decision,
            preference: preference,
            reason: hostConfiguration.localAuthenticationReason
        )
        accessState = nextState

        guard shouldAttemptUnlock else {
            return
        }

        switch nextState {
        case .unlocked:
            await releaseControlClient.track(.authenticationAppUnlockCompleted(
                result: "success",
                lockMode: AuthenticationAppLockMode.launchOnly.rawValue,
                variationKey: decision.variationKey
            ))
        case .locked(let reason):
            await releaseControlClient.track(.authenticationAppUnlockFailed(
                result: reason == "Authentication was canceled." ? "canceled" : "failed",
                lockMode: AuthenticationAppLockMode.launchOnly.rawValue,
                variationKey: decision.variationKey
            ))
        }
    }
}
