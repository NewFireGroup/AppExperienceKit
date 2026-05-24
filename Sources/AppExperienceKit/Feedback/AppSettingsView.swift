import SwiftUI

enum AppSettingsDestination: CaseIterable {
    case featurePreviews
    case accountSecurity
    case productFeedback

    var title: String {
        switch self {
        case .featurePreviews:
            return "Feature Previews"
        case .accountSecurity:
            return "Account & Security"
        case .productFeedback:
            return "Product Feedback"
        }
    }

    var systemImage: String {
        switch self {
        case .featurePreviews:
            return "switch.2"
        case .accountSecurity:
            return "lock.shield"
        case .productFeedback:
            return FeedbackVisualIdentity.systemImage
        }
    }
}

public struct AppSettingsView: View {
    private let publicReleaseHistory: PublicReleaseHistory
    private let versionHistory: VersionHistory
    private let bundle: Bundle
    private let hostConfiguration: AppExperienceHostConfiguration
    private let githubFeedbackConfiguration: GitHubFeedbackConfiguration
    private let featurePreviewReleaseControls: [ReleaseControlDescriptor]

    public init(
        publicReleaseHistory: PublicReleaseHistory = .bundled(),
        versionHistory: VersionHistory = .bundled(),
        bundle: Bundle = .main,
        hostConfiguration: AppExperienceHostConfiguration? = nil,
        githubFeedbackConfiguration: GitHubFeedbackConfiguration? = nil,
        featurePreviewReleaseControls: [ReleaseControlDescriptor] = ReleaseControlDescriptor.packageDefaults
    ) {
        self.publicReleaseHistory = publicReleaseHistory
        self.versionHistory = versionHistory
        self.bundle = bundle
        self.hostConfiguration = hostConfiguration ?? .mainBundle(bundle: bundle)
        self.githubFeedbackConfiguration = githubFeedbackConfiguration ?? .mainBundle(bundle: bundle)
        self.featurePreviewReleaseControls = featurePreviewReleaseControls
    }

    public var body: some View {
        List {
            Section {
                NavigationLink {
                    AccountSecuritySettingsView(
                        hostConfiguration: hostConfiguration,
                        githubFeedbackConfiguration: githubFeedbackConfiguration
                    )
                } label: {
                    Label(AppSettingsDestination.accountSecurity.title, systemImage: AppSettingsDestination.accountSecurity.systemImage)
                }

                NavigationLink {
                    ReleaseControlFlagStatesView(releaseControls: featurePreviewReleaseControls)
                } label: {
                    Label(AppSettingsDestination.featurePreviews.title, systemImage: AppSettingsDestination.featurePreviews.systemImage)
                }

                NavigationLink {
                    FeedbackSettingsView(githubFeedbackConfiguration: githubFeedbackConfiguration)
                } label: {
                    FeedbackIdentityLabel("Product Feedback")
                }
            }

            Section("About") {
                LabeledContent("Name", value: appDisplayName)
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)

                NavigationLink {
                    VersionHistoryView(
                        releaseHistory: publicReleaseHistory,
                        fallbackHistory: versionHistory
                    )
                } label: {
                    Label("Version History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var appDisplayName: String {
        hostConfiguration.displayName
    }

    private var appVersion: String {
        publicReleaseHistory.aboutDisplayVersion(
            fallbackHistory: versionHistory,
            bundleShortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
    }

    private var buildNumber: String {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}

public struct AccountSecuritySettingsView: View {
    @Environment(\.releaseControlClient) private var releaseControlClient

    @StateObject private var githubAuth: GitHubAuthViewModel
    @State private var authenticationDecision: ReleaseControlDecision = .disabled(.authenticationFeature)
    @State private var authenticationPreference: ReleaseControlPreference = .systemDefault
    @State private var isAppLockEnabled = false

    private let authenticationPreferenceStore: ReleaseControlPreferenceStore
    private let identityStore: AppIdentityStore
    private let hostConfiguration: AppExperienceHostConfiguration

    public init(
        authenticationPreferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore(),
        identityStore: AppIdentityStore = AppIdentityStore(),
        hostConfiguration: AppExperienceHostConfiguration = .mainBundle(),
        githubFeedbackConfiguration: GitHubFeedbackConfiguration = .mainBundle()
    ) {
        self.authenticationPreferenceStore = authenticationPreferenceStore
        self.identityStore = identityStore
        self.hostConfiguration = hostConfiguration
        _githubAuth = StateObject(wrappedValue: GitHubAuthViewModel(
            configuration: githubFeedbackConfiguration,
            identityStore: identityStore
        ))
    }

    public var body: some View {
        List {
            if showsAccountSecurity {
                Section {
                    if authenticationDecision.isAuthenticationAppLockAvailable(preference: authenticationPreference) {
                        Toggle("Require Authentication on Launch", isOn: appLockBinding)
                        Text("Requires Face ID, Touch ID, or device passcode when \(hostConfiguration.displayName) opens.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if authenticationDecision.isAuthenticationGitHubLinkingAvailable(preference: authenticationPreference) {
                        GitHubConnectionControls(
                            githubAuth: githubAuth,
                            identityStore: identityStore,
                            onStartAuthentication: { Task { await startGitHubAuthentication() } },
                            onCompleteAuthentication: { Task { await completeGitHubAuthentication() } },
                            onDisconnect: { disconnectGitHub() }
                        )
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "Account & Security",
                        systemImage: AppSettingsDestination.accountSecurity.systemImage,
                        description: Text("Account security is disabled for the current release-control user.")
                    )
                }
            }
        }
        .navigationTitle("Account & Security")
        .task {
            await refreshAccountSecuritySettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: ReleaseControlPreferenceStore.preferenceDidChangeNotification)) { _ in
            Task {
                await refreshAccountSecuritySettings()
            }
        }
    }

    private var showsAccountSecurity: Bool {
        authenticationDecision.isAuthenticationAppLockAvailable(preference: authenticationPreference) ||
            authenticationDecision.isAuthenticationGitHubLinkingAvailable(preference: authenticationPreference)
    }

    private var appLockBinding: Binding<Bool> {
        Binding(get: {
            isAppLockEnabled
        }, set: { newValue in
            updateAppLockPreference(newValue)
        })
    }

    @MainActor
    private func refreshAccountSecuritySettings() async {
        authenticationDecision = await releaseControlClient.activeDecision(
            for: .authenticationFeature,
            preferenceStore: authenticationPreferenceStore
        )
        authenticationPreference = authenticationPreferenceStore.preference(for: .authenticationFeature)
        isAppLockEnabled = identityStore.isAppLockEnabled
    }

    private func updateAppLockPreference(_ isEnabled: Bool) {
        let previousValue = isAppLockEnabled
        isAppLockEnabled = isEnabled
        identityStore.setAppLockEnabled(isEnabled)

        guard previousValue != isEnabled else {
            return
        }

        Task {
            await releaseControlClient.track(isEnabled
                ? .authenticationAppLockEnabled(
                    launchSource: "settings",
                    lockMode: authenticationDecision.authenticationAppLockMode.rawValue,
                    variationKey: authenticationDecision.variationKey
                )
                : .authenticationAppLockDisabled(
                    launchSource: "settings",
                    lockMode: authenticationDecision.authenticationAppLockMode.rawValue,
                    variationKey: authenticationDecision.variationKey
                )
            )
        }
    }

    private func startGitHubAuthentication() async {
        if authenticationDecision.isAuthenticationGitHubLinkingAvailable(preference: authenticationPreference) {
            await releaseControlClient.track(.authenticationGitHubLinkStarted(
                launchSource: "settings",
                variationKey: authenticationDecision.variationKey
            ))
        }

        await githubAuth.startAuthentication()
    }

    private func completeGitHubAuthentication() async {
        await githubAuth.completeAuthentication()

        if authenticationDecision.isAuthenticationGitHubLinkingAvailable(preference: authenticationPreference),
           githubAuth.connectionState == .connected {
            await releaseControlClient.track(.authenticationGitHubLinked(
                launchSource: "settings",
                variationKey: authenticationDecision.variationKey
            ))
        }
    }

    private func disconnectGitHub() {
        let wasConnected = githubAuth.connectionState == .connected
        githubAuth.disconnect()

        guard wasConnected,
              authenticationDecision.isAuthenticationGitHubLinkingAvailable(preference: authenticationPreference)
        else {
            return
        }

        Task {
            await releaseControlClient.track(.authenticationGitHubUnlinked(
                launchSource: "settings",
                variationKey: authenticationDecision.variationKey
            ))
        }
    }
}

public struct FeedbackSettingsView: View {
    @Environment(\.releaseControlClient) private var releaseControlClient
    @AppStorage(EarlyAdopterSettingsStore.appleAssistKey) private var enableAppleAssist = false
    @AppStorage(EarlyAdopterSettingsStore.startFeedbackWithAppleAssistKey) private var startFeedbackWithAppleAssist = false

    @StateObject private var githubAuth: GitHubAuthViewModel
    @State private var feedbackDecision: ReleaseControlDecision = .disabled(.feedbackFeature)
    @State private var authenticationDecision: ReleaseControlDecision = .disabled(.authenticationFeature)
    @State private var authenticationPreference: ReleaseControlPreference = .systemDefault
    @State private var aiAvailability: FeedbackAIAvailability = .unavailable("Apple Intelligence availability has not loaded")
    @State private var isShowingFeedbackStoreResetConfirmation = false
    @State private var isResettingFeedbackStore = false
    @State private var feedbackStoreResetMessage: String?

    private let authenticationPreferenceStore: ReleaseControlPreferenceStore
    private let identityStore: AppIdentityStore

    public init(
        authenticationPreferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore(),
        identityStore: AppIdentityStore = AppIdentityStore(),
        githubFeedbackConfiguration: GitHubFeedbackConfiguration = .mainBundle()
    ) {
        self.authenticationPreferenceStore = authenticationPreferenceStore
        self.identityStore = identityStore
        _githubAuth = StateObject(wrappedValue: GitHubAuthViewModel(
            configuration: githubFeedbackConfiguration,
            identityStore: identityStore
        ))
    }

    public var body: some View {
        List {
            if feedbackDecision.showsFeedbackSettings {
                Section {
                    if FeedbackAIAssistSettings.showsSettingsToggle(decision: feedbackDecision) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Enable Feedback Assist", isOn: appleAssistBinding)
                                .disabled(!canEnableAppleAssist)

                            Text("Utilizes Apple Foundation models to take your input and help populate our feedback form")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Divider()

                            Toggle("Start with Assist", isOn: startFeedbackWithAppleAssistBinding)
                                .disabled(!enableAppleAssist || !canEnableAppleAssist)

                            Text("Feedback opens with Feedback Assist before showing the form.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let message = FeedbackAIAssistSettings.disabledMessage(for: aiAvailability) {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !showsAuthenticationGitHubLinking {
                        GitHubConnectionControls(
                            githubAuth: githubAuth,
                            identityStore: identityStore,
                            onStartAuthentication: { Task { await githubAuth.startAuthentication() } },
                            onCompleteAuthentication: { Task { await githubAuth.completeAuthentication() } },
                            onDisconnect: { githubAuth.disconnect() }
                        )
                    }
                } header: {
                    Text("Early Adopter Feedback")

                } footer: {
                }
                .appExperienceListSectionSpacing(20)

                Section {
                    VStack(alignment: .leading, spacing: 20) {
                        if isResettingFeedbackStore {
                            ProgressView("Resetting feedback store...")
                        }

                        if let feedbackStoreResetMessage {
                            Text(feedbackStoreResetMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Button("Start Over with Feedback Store", role: .destructive) {
                                isShowingFeedbackStoreResetConfirmation = true
                            }
                            .disabled(isResettingFeedbackStore)

                            Text("Deletes feedback drafts and submitted feedback saved on this device. This cannot be undone.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Contains actions that are often irreversible and cannot be undone.")
                }
                .appExperienceListSectionSpacing(20)
            } else {
                Section {
                    ContentUnavailableView(
                        "Early Adopters",
                        systemImage: "person.crop.circle.badge.checkmark",
                        description: Text("Early adopter feedback is disabled for the current release-control user.")
                    )
                }
            }
        }
        .navigationTitle(AppSettingsDestination.productFeedback.title)
        .task {
            await refreshFeedbackSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: ReleaseControlPreferenceStore.preferenceDidChangeNotification)) { _ in
            Task {
                await refreshFeedbackSettings()
            }
        }
        .confirmationDialog(
            "Start over with feedback store?",
            isPresented: $isShowingFeedbackStoreResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Feedback Store", role: .destructive) {
                Task { await resetFeedbackStore() }
            }
            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text("This permanently deletes feedback drafts and submitted feedback saved on this device. You cannot get old items back.")
        }
    }

    private var canEnableAppleAssist: Bool {
        FeedbackAIAssistSettings.canEnable(availability: aiAvailability)
    }

    private var showsAuthenticationGitHubLinking: Bool {
        authenticationDecision.isAuthenticationGitHubLinkingAvailable(preference: authenticationPreference)
    }

    private var appleAssistBinding: Binding<Bool> {
        Binding(get: {
            enableAppleAssist && canEnableAppleAssist
        }, set: { newValue in
            let isEnabled = newValue && canEnableAppleAssist
            enableAppleAssist = isEnabled
            if !isEnabled {
                startFeedbackWithAppleAssist = false
            }
        })
    }

    private var startFeedbackWithAppleAssistBinding: Binding<Bool> {
        Binding(get: {
            startFeedbackWithAppleAssist && enableAppleAssist && canEnableAppleAssist
        }, set: { newValue in
            startFeedbackWithAppleAssist = newValue && enableAppleAssist && canEnableAppleAssist
        })
    }

    @MainActor
    private func refreshFeedbackSettings() async {
        feedbackDecision = await releaseControlClient.activeDecision(for: .feedbackFeature)
        authenticationDecision = await releaseControlClient.activeDecision(
            for: .authenticationFeature,
            preferenceStore: authenticationPreferenceStore
        )
        authenticationPreference = authenticationPreferenceStore.preference(for: .authenticationFeature)
        aiAvailability = FeedbackAIClientFactory.makeClient().availability()

        if !FeedbackAIAssistSettings.showsSettingsToggle(decision: feedbackDecision) || !canEnableAppleAssist {
            enableAppleAssist = false
            startFeedbackWithAppleAssist = false
        } else if !enableAppleAssist {
            startFeedbackWithAppleAssist = false
        }
    }

    @MainActor
    private func resetFeedbackStore() async {
        isResettingFeedbackStore = true
        feedbackStoreResetMessage = nil
        defer { isResettingFeedbackStore = false }

        do {
            try FeedbackDraftStore.resetLiveStore()
            feedbackStoreResetMessage = "Feedback store reset. New feedback will start from an empty store."
        } catch {
            feedbackStoreResetMessage = error.localizedDescription
        }
    }
}

private extension View {
    @ViewBuilder
    func appExperienceListSectionSpacing(_ spacing: CGFloat) -> some View {
        #if os(iOS)
        self.listSectionSpacing(spacing)
        #else
        self
        #endif
    }
}

private struct GitHubConnectionControls: View {
    @ObservedObject var githubAuth: GitHubAuthViewModel
    let identityStore: AppIdentityStore
    let onStartAuthentication: () -> Void
    let onCompleteAuthentication: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        switch githubAuth.connectionState {
        case .connected:
            if let identity = identityStore.linkedGitHubIdentity {
                HStack {
                    Text("GitHub")
                    Spacer()
                    Text(identity.login)
                        .foregroundStyle(identity.isCredentialStale ? .orange : .secondary)
                }
            }

            Button("Disconnect from GitHub", role: .destructive) {
                onDisconnect()
            }
        case .disconnected:
            Button("Authenticate with GitHub") {
                onStartAuthentication()
            }
        }

        if let deviceCode = githubAuth.deviceCode {
            VStack(alignment: .leading, spacing: 8) {
                Text(deviceCode.userCode)
                    .font(.title3.monospaced().weight(.semibold))
                    .textSelection(.enabled)
                Link("Open GitHub device login", destination: deviceCode.verificationURI)
                Button("Finish GitHub Login") {
                    onCompleteAuthentication()
                }
            }
            .padding(.vertical, 4)
        }

        if githubAuth.isWorking {
            ProgressView()
        }

        if let message = githubAuth.message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
