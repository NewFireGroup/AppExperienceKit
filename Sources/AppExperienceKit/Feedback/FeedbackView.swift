import SwiftUI

public struct FeedbackView: View {
    @Environment(\.releaseControlClient) private var releaseControlClient
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @AppStorage(EarlyAdopterSettingsStore.appleAssistKey) private var enableAppleAssist = false
    @AppStorage(EarlyAdopterSettingsStore.startFeedbackWithAppleAssistKey) private var startFeedbackWithAppleAssist = false

    @State private var store: FeedbackDraftStore?
    @State private var feedbackDecision: ReleaseControlDecision = .disabled(.feedbackFeature)
    @State private var aiAvailability: FeedbackAIAvailability = .unavailable("Apple Intelligence availability has not loaded")
    @State private var category: FeedbackCategory = .general
    @State private var source: FeedbackDraftSource = .manual
    @State private var roughNote = ""
    @State private var title = ""
    @State private var summary = ""
    @State private var stepsToReproduce = ""
    @State private var expectedBehavior = ""
    @State private var actualBehavior = ""
    @State private var additionalContext = ""
    @State private var statusMessage: String?
    @State private var aiAssistStatusMessage: String?
    @State private var isWorking = false
    @State private var currentDraft: FeedbackDraft?
    @State private var isShowingClearConfirmation = false
    @State private var isShowingAIAssistSheet = false
    @State private var isShowingAIAssistLaunchScreen = false
    @State private var shouldTrackAIAssistCancellation = false
    @State private var hasHandledAIAssistLaunchPreference = false
    @State private var telemetryState = FeedbackTelemetryState()

    private let tokenStore: GitHubTokenStore
    private let issueClient: any GitHubIssueClient
    private let configuration: GitHubFeedbackConfiguration
    private let authenticationPreferenceStore: ReleaseControlPreferenceStore
    private let identityStore: AppIdentityStore
    private let launchContext: FeedbackLaunchContext
    private let showsPopOutButton: Bool
    private let launchSurface: FeedbackAIAssistLaunchSurface
    private let onSubmitted: @MainActor () -> Void

    public init(
        launchContext: FeedbackLaunchContext = FeedbackLaunchContext(),
        showsPopOutButton: Bool = true,
        launchSurface: FeedbackAIAssistLaunchSurface = .standaloneWindow,
        tokenStore: GitHubTokenStore = KeychainGitHubTokenStore(),
        issueClient: any GitHubIssueClient = GitHubRESTIssueClient(),
        configuration: GitHubFeedbackConfiguration = .mainBundle(),
        authenticationPreferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore(),
        identityStore: AppIdentityStore = AppIdentityStore(),
        onSubmitted: @escaping @MainActor () -> Void = {}
    ) {
        self.launchContext = launchContext
        self.showsPopOutButton = showsPopOutButton
        self.launchSurface = launchSurface
        self.tokenStore = tokenStore
        self.issueClient = issueClient
        self.configuration = configuration
        self.authenticationPreferenceStore = authenticationPreferenceStore
        self.identityStore = identityStore
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        Group {
            if isShowingAIAssistLaunchScreen {
                aiAssistForm
            } else if feedbackDecision.showsFeedbackNavigation {
                feedbackForm
            } else {
                ContentUnavailableView(
                    "Feedback",
                    systemImage: "bubble.left.and.text.bubble.right",
                    description: Text("Feedback is not enabled for this release-control user.")
                )
            }
        }
        .navigationTitle(isShowingAIAssistLaunchScreen ? "Feedback Assist" : "Feedback")
        .toolbar {
            if isShowingAIAssistLaunchScreen {
                aiAssistLaunchToolbar
            } else {
                feedbackFormToolbar
            }
        }
        .sheet(isPresented: $isShowingAIAssistSheet, onDismiss: {
            Task { await trackAIAssistCanceledIfNeeded() }
        }) {
            NavigationStack {
                aiAssistForm
                    .navigationTitle("Feedback Assist")
                    .toolbar {
                        aiAssistSheetToolbar
                    }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible) // Adds the grabber handle
        .task {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: ReleaseControlPreferenceStore.preferenceDidChangeNotification)) { _ in
            Task {
                await load()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FeedbackDraftStore.didResetNotification)) { _ in
            handleFeedbackStoreReset()
        }
        .onChange(of: formStartSignal) { _, _ in
            Task { await trackFormStartedIfNeeded() }
        }
        .confirmationDialog(
            "Clear feedback form?",
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Form", role: .destructive) {
                Task { await clearForm() }
            }
            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text("This removes the current draft and clears all fields.")
        }
        .onDisappear {
            Task {
                await saveDraftIfNeeded()
                await trackAbandonedIfNeeded()
            }
        }
    }

    private var feedbackForm: some View {
        Form {
            if isWorking {
                ProgressView()
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if launchContext.source != .feedbackNavigation {
                Section("Context") {
                    LabeledContent("Opened from", value: launchContext.displayName)
                }
            }

            Section {
                Picker("Category", selection: $category) {
                    ForEach(FeedbackCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }

                detailTextField("Title", text: $title)
                detailTextEditor("Summary", text: $summary, minHeight: 100)
            } header: {
                FeedbackIdentityLabel("Feedback")
            }

            Section("Details") {
                detailTextEditor("Steps to reproduce", text: $stepsToReproduce, minHeight: 80)
                detailTextField("Expected behavior", text: $expectedBehavior)
                detailTextField("Actual behavior", text: $actualBehavior)
                detailTextField("Additional context", text: $additionalContext)
            }
        }
    }

    @ToolbarContentBuilder
    private var feedbackFormToolbar: some ToolbarContent {
        if feedbackDecision.showsFeedbackNavigation && showsPopOutButton && !AppExperiencePlatform.isPhone {
            ToolbarItemGroup(placement: .automatic) {
                Button("Open in New Window", systemImage: "arrow.up.right.square") {
                    Task { await popOut() }
                }
                .help("Open the feedback form in a separate window")
                .disabled(isWorking)
            }
        }

        ToolbarItemGroup(placement: .automatic) {
            if showsAIAssistToolbarButton {
                Button("AI assist", systemImage: "apple.intelligence") {
                    openAIAssistSheet()
                }
                .help("Let us help you fill out this form")
                .disabled(isWorking)
            }

            Button("Clear form", systemImage: "eraser.trianglebadge.exclamationmark", role: .destructive) {
                isShowingClearConfirmation = true
            }
            .help("Clear the feedback form and start over")
            .disabled(!canClearForm)
        }

        ToolbarSpacer()

        ToolbarItem(placement: .confirmationAction) {
            let actions = FeedbackSubmitActions.availableActions(
                githubConnectionState: githubConnectionState,
                allowsGitHubSubmission: configuration.isIssueSubmissionConfigured
            )

            if actions.contains(.github) {
                Menu {
                    ForEach(actions, id: \.self) { action in
                        Button(action.title, systemImage: action.systemImage) {
                            Task { await submit(action) }
                        }
                    }
                } label: {
                    Label(FeedbackSubmitActions.primaryTitle, systemImage: "paperplane")
                }
                .disabled(!canSubmitFeedback)
            } else {
                Button(FeedbackSubmitActions.primaryTitle, systemImage: FeedbackSubmitAction.local.systemImage) {
                    Task { await submit(.local) }
                }
                .disabled(!canSubmitFeedback)
            }
        }
    }

    @ToolbarContentBuilder
    private var aiAssistLaunchToolbar: some ToolbarContent {
        aiAssistToolbar(submit: {
            Task { await runAIAssistFromLaunchScreen() }
        })
    }

    @ToolbarContentBuilder
    private var aiAssistSheetToolbar: some ToolbarContent {
        aiAssistToolbar(submit: {
            Task { await runAIAssistFromSheet() }
        })
    }

    @ToolbarContentBuilder
    private func aiAssistToolbar(
        submit: @escaping @MainActor () -> Void
    ) -> some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(role: .confirm) {
                submit()
            }
            .disabled(roughNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            .keyboardShortcut(.defaultAction)
        }
    }

    @MainActor
    private func load() async {
        feedbackDecision = await releaseControlClient.activeDecision(for: .feedbackFeature)
        aiAvailability = makeAIClient().availability()
        if !FeedbackAIAssistSettings.showsSettingsToggle(decision: feedbackDecision) ||
            !FeedbackAIAssistSettings.canEnable(availability: aiAvailability) {
            enableAppleAssist = false
            startFeedbackWithAppleAssist = false
        } else if !enableAppleAssist {
            startFeedbackWithAppleAssist = false
        }

        if let event = telemetryState.featureOpenedEvent(
            launchContext: launchContext,
            decision: feedbackDecision
        ) {
            await releaseControlClient.track(event)
        }
        if store == nil {
            do {
                store = try FeedbackDraftStore.live()
            } catch {
                statusMessage = error.localizedDescription
            }
        }

        if currentDraft == nil,
           let store {
            do {
                let draft: FeedbackDraft?
                if let draftID = launchContext.draftID {
                    draft = try store.fetchDraft(id: draftID)
                } else {
                    draft = try store.fetchLatestRestorableDraft()
                }
                if let draft {
                    currentDraft = draft
                    apply(draft)
                }
            } catch {
                statusMessage = error.localizedDescription
            }
        }

        openAIAssistOnLaunchIfNeeded()
    }

    private var aiAssistForm: some View {
        FeedbackAIAssistPromptForm(
            roughNote: $roughNote,
            isWorking: isWorking,
            statusMessage: aiAssistStatusMessage,
            onSkip: { goDirectlyToFeedbackForm() }
        )
    }

    private func detailTextEditor(
        _ title: String,
        text: Binding<String>,
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !text.wrappedValue.isEmpty {
                detailFieldLabel(title)
            }

            TextEditor(text: text)
                .frame(minHeight: minHeight)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(title)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }
        }
    }

    private func detailTextField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !text.wrappedValue.isEmpty {
                detailFieldLabel(title)
            }

            TextField(title, text: text, axis: .vertical)
        }
    }

    private func detailFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var canSubmitFeedback: Bool {
        !isWorking &&
        feedbackDecision.showsFeedbackNavigation &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canClearForm: Bool {
        !isWorking && hasFormStartInput
    }

    private var githubConnectionState: GitHubConnectionState {
        tokenStore.loadToken() == nil ? .disconnected : .connected
    }

    private var showsAIAssistToolbarButton: Bool {
        FeedbackAIAssistSettings.showsToolbarButton(
            decision: feedbackDecision,
            isUserEnabled: enableAppleAssist,
            availability: aiAvailability
        )
    }

    private var shouldStartWithAIAssistOnLaunch: Bool {
        FeedbackAIAssistSettings.startsFeedbackWithAIAssist(
            decision: feedbackDecision,
            isUserEnabled: enableAppleAssist,
            isStartWithAssistEnabled: startFeedbackWithAppleAssist,
            availability: aiAvailability,
            launchSurface: launchSurface,
            isEditingDraft: launchContext.draftID != nil,
            hasMeaningfulContent: hasFormStartInput
        )
    }

    private var formStartSignal: String {
        [
            category.rawValue,
            title,
            summary,
            stepsToReproduce,
            expectedBehavior,
            actualBehavior,
            additionalContext,
            roughNote
        ].joined(separator: "\n")
    }

    private var snapshot: FeedbackFormSnapshot {
        FeedbackFormSnapshot(
            category: category,
            source: source,
            title: title,
            summary: summary,
            stepsToReproduce: stepsToReproduce,
            expectedBehavior: expectedBehavior,
            actualBehavior: actualBehavior,
            additionalContext: additionalContext,
            roughNote: roughNote
        )
    }

    private var feedbackDiagnostics: FeedbackDiagnostics {
        FeedbackDiagnostics.current(
            aiAvailability: makeAIClient().availability().displayName,
            releaseControl: "feedback_feature:\(feedbackDecision.isEnabled ? "on" : "off")",
            launchContext: launchContext
        )
    }

    private var hasFormStartInput: Bool {
        snapshot.hasMeaningfulContent
    }

    @MainActor
    private func openAIAssistSheet() {
        aiAssistStatusMessage = nil
        shouldTrackAIAssistCancellation = true
        isShowingAIAssistSheet = true
        Task { await trackAIAssistOpened() }
    }

    @MainActor
    private func openAIAssistOnLaunchIfNeeded() {
        guard !hasHandledAIAssistLaunchPreference else { return }

        hasHandledAIAssistLaunchPreference = true
        guard shouldStartWithAIAssistOnLaunch else { return }

        aiAssistStatusMessage = nil
        shouldTrackAIAssistCancellation = false
        isShowingAIAssistLaunchScreen = true
        Task { await trackAIAssistOpened() }
    }

    @MainActor
    private func goDirectlyToFeedbackForm() {
        shouldTrackAIAssistCancellation = false
        isShowingAIAssistSheet = false
        isShowingAIAssistLaunchScreen = false
    }

    @MainActor
    private func cancelAIAssistSheet() {
        Task { await trackAIAssistCanceledIfNeeded() }
        isShowingAIAssistSheet = false
    }

    @MainActor
    private func runAIAssistFromLaunchScreen() async {
        shouldTrackAIAssistCancellation = false
        if await runAIAssist() {
            isShowingAIAssistLaunchScreen = false
        }
    }

    @MainActor
    private func runAIAssistFromSheet() async {
        shouldTrackAIAssistCancellation = false
        if await runAIAssist() {
            isShowingAIAssistSheet = false
        }
    }

    @MainActor
    @discardableResult
    private func runAIAssist() async -> Bool {
        isWorking = true
        aiAssistStatusMessage = nil
        defer { isWorking = false }

        do {
            let store = try ensureFeedbackStore()
            await trackFormStartedIfNeeded()
            let update = try await FeedbackAIAssistSession.apply(
                message: roughNote,
                snapshot: snapshot,
                currentDraft: currentDraft,
                store: store,
                diagnostics: feedbackDiagnostics,
                client: makeAIClient()
            )
            currentDraft = update.draft
            apply(update.snapshot)
            await trackAIAssist(result: update.result.mode.telemetryResult)
            statusMessage = update.result.reason ?? "AI Assist updated the draft."
            aiAssistStatusMessage = nil
            return true
        } catch {
            await trackAIAssist(result: "failed")
            statusMessage = error.localizedDescription
            aiAssistStatusMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    private func submit(_ action: FeedbackSubmitAction) async {
        isWorking = true
        defer { isWorking = false }

        do {
            let store = try ensureFeedbackStore()
            await trackFormStartedIfNeeded()
            let draft = try makeDraft(store: store)
            guard action == .github else {
                try store.markSubmitted(draft, issueURL: nil)
                statusMessage = "Submitted locally. You can view, share, or export it from My Feedback."
                await trackSubmittedIfNeeded(action: .local)
                handleSubmitOutcome(.submitted)
                return
            }

            guard let token = tokenStore.loadToken() else {
                statusMessage = "Saved locally. Connect GitHub in Settings to submit this feedback."
                handleSubmitOutcome(.savedPendingAuthentication)
                return
            }
            let payload = FeedbackIssueRenderer().payload(
                for: draft,
                owner: configuration.owner,
                repo: configuration.repo
            )
            let issueURL = try await issueClient.createIssue(payload, token: token)
            try store.markSubmitted(draft, issueURL: issueURL)
            statusMessage = "Submitted to GitHub and saved in My Feedback: \(issueURL.absoluteString)"
            await trackGitHubCredentialUsedIfNeeded()
            await trackSubmittedIfNeeded(action: .github)
            handleSubmitOutcome(.submitted)
        } catch GitHubIssueClientError.authenticationRequired {
            identityStore.markGitHubCredentialStale()
            if let currentDraft {
                try? store?.markFailed(
                    currentDraft,
                    message: GitHubIssueClientError.authenticationRequired.localizedDescription
                )
            }
            statusMessage = GitHubIssueClientError.authenticationRequired.localizedDescription
            handleSubmitOutcome(.failed)
        } catch {
            if let currentDraft {
                try? store?.markFailed(currentDraft, message: error.localizedDescription)
            }
            statusMessage = error.localizedDescription
            handleSubmitOutcome(.failed)
        }
    }

    @MainActor
    private func handleSubmitOutcome(_ outcome: FeedbackSubmitOutcome) {
        FeedbackSubmitPresentation {
            onSubmitted()
            dismiss()
        }
        .handle(outcome)
    }

    @MainActor
    private func makeDraft(store: FeedbackDraftStore) throws -> FeedbackDraft {
        let diagnostics = feedbackDiagnostics
        let draft: FeedbackDraft
        if let currentDraft {
            draft = currentDraft
            draft.diagnostics = diagnostics
        } else {
            draft = try store.createDraft(category: category, source: source, diagnostics: diagnostics)
            currentDraft = draft
        }
        snapshot.apply(to: draft)
        try store.save(draft)
        return draft
    }

    @MainActor
    private func ensureFeedbackStore() throws -> FeedbackDraftStore {
        if let store {
            return store
        }

        let loadedStore = try FeedbackDraftStore.live()
        store = loadedStore
        return loadedStore
    }

    @MainActor
    private func apply(_ draft: FeedbackDraft) {
        apply(FeedbackFormSnapshot(draft: draft))
    }

    @MainActor
    private func apply(_ snapshot: FeedbackFormSnapshot) {
        category = snapshot.category
        source = snapshot.source
        title = snapshot.title
        summary = snapshot.summary
        stepsToReproduce = snapshot.stepsToReproduce
        expectedBehavior = snapshot.expectedBehavior
        actualBehavior = snapshot.actualBehavior
        additionalContext = snapshot.additionalContext
        roughNote = snapshot.roughNote
    }

    @MainActor
    private func clearForm() async {
        isWorking = true
        defer { isWorking = false }

        do {
            if let currentDraft {
                try store?.deleteDraft(currentDraft)
            }
            currentDraft = nil
            apply(FeedbackFormSnapshot())
            isShowingAIAssistSheet = false
            shouldTrackAIAssistCancellation = false
            telemetryState = FeedbackTelemetryState()
            statusMessage = "Feedback form cleared."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleFeedbackStoreReset() {
        store = nil
        currentDraft = nil
        isWorking = false
        isShowingAIAssistSheet = false
        shouldTrackAIAssistCancellation = false
        aiAssistStatusMessage = nil
        telemetryState = FeedbackTelemetryState()
        apply(FeedbackFormSnapshot())
        statusMessage = "Feedback store was reset."
    }

    @MainActor
    @discardableResult
    private func saveDraftIfNeeded() async -> FeedbackDraft? {
        guard hasFormStartInput else { return nil }

        do {
            let store = try ensureFeedbackStore()
            return try makeDraft(store: store)
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    private func popOut() async {
        let draft = await saveDraftIfNeeded()
        let context = draft.map { launchContext.withDraftID($0.id) } ?? launchContext
        openWindow(id: FeedbackLaunchContext.windowID, value: context)
    }

    private func makeAIClient() -> any FeedbackAIClient {
        FeedbackAIClientFactory.makeClient()
    }

    @MainActor
    private func trackFormStartedIfNeeded() async {
        guard hasFormStartInput else { return }
        if let event = telemetryState.formStartedEvent(
            category: category,
            source: source,
            launchContext: launchContext,
            decision: feedbackDecision
        ) {
            await releaseControlClient.track(event)
        }
    }

    @MainActor
    private func trackAIAssistOpened() async {
        let event = telemetryState.aiAssistOpenedEvent(
            category: category,
            source: source,
            launchContext: launchContext,
            decision: feedbackDecision
        )
        await releaseControlClient.track(event)
    }

    @MainActor
    private func trackAIAssist(result: String) async {
        let event = telemetryState.aiAssistUsedEvent(
            category: category,
            source: source,
            result: result,
            launchContext: launchContext,
            decision: feedbackDecision
        )
        await releaseControlClient.track(event)
    }

    @MainActor
    private func trackAIAssistCanceledIfNeeded() async {
        guard shouldTrackAIAssistCancellation else { return }
        shouldTrackAIAssistCancellation = false
        let event = telemetryState.aiAssistCanceledEvent(
            category: category,
            source: source,
            launchContext: launchContext,
            decision: feedbackDecision
        )
        await releaseControlClient.track(event)
    }

    @MainActor
    private func trackSubmittedIfNeeded(action: FeedbackSubmitAction) async {
        if let event = telemetryState.formSubmittedEvent(
            category: category,
            source: source,
            action: action,
            launchContext: launchContext,
            decision: feedbackDecision
        ) {
            await releaseControlClient.track(event)
        }
    }

    @MainActor
    private func trackGitHubCredentialUsedIfNeeded() async {
        let decision = await releaseControlClient.activeDecision(
            for: .authenticationFeature,
            preferenceStore: authenticationPreferenceStore
        )
        let preference = authenticationPreferenceStore.preference(for: .authenticationFeature)
        guard decision.isAuthenticationGitHubLinkingAvailable(preference: preference) else {
            return
        }

        await releaseControlClient.track(.authenticationGitHubCredentialUsed(
            launchSource: launchContext.source.telemetryValue,
            destination: FeedbackSubmitAction.github.telemetryDestination,
            variationKey: decision.variationKey
        ))
    }

    @MainActor
    private func trackAbandonedIfNeeded() async {
        if let event = telemetryState.formAbandonedEvent(
            category: category,
            source: source,
            launchContext: launchContext,
            decision: feedbackDecision
        ) {
            await releaseControlClient.track(event)
        }
    }
}

struct FeedbackIdentityIcon: View {
    var size: CGFloat = 17

    var body: some View {
        Image(systemName: FeedbackVisualIdentity.systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(FeedbackVisualIdentity.tint)
            .frame(width: size, height: size)
    }
}

struct FeedbackAIAssistPromptForm: View {
    @Binding var roughNote: String
    let isWorking: Bool
    let statusMessage: String?
    let onSkip: @MainActor () -> Void

    var body: some View {
        Form {
            Section {
                TextEditor(text: $roughNote)
                    .frame(minHeight: 160)
                    .disabled(isWorking)
                    .overlay(alignment: .topLeading) {
                        if roughNote.isEmpty {
                            Text("Describe what happened. Feedback Assist can help turn it into issue fields.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                    }

                Button("Skip to feedback form", systemImage: "chevron.forward") {
                    onSkip()
                }
                .disabled(isWorking)
            }

            if isWorking {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Applying Feedback Assist...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

public struct FeedbackIdentityLabel: View {
    private let title: LocalizedStringKey

    public init(_ title: LocalizedStringKey) {
        self.title = title
    }

    public var body: some View {
        Label {
            Text(title)
        } icon: {
            FeedbackIdentityIcon()
        }
    }
}

enum FeedbackVisualIdentity {
    static let systemImage = "bubble.left.and.text.bubble.right"
    static let tint = Color.purple
}

public struct FeedbackSidebarToolbarButton: View {
    @Environment(\.releaseControlClient) private var releaseControlClient
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appLaunchSession: AppLaunchSession
    @Environment(\.feedbackPaneOpener) private var feedbackPaneOpener

    @State private var feedbackDecision: ReleaseControlDecision = .disabled(.feedbackFeature)

    private let launchContext: FeedbackLaunchContext

    public init(source: FeedbackLaunchSource = .toolbar) {
        self.launchContext = FeedbackLaunchContext(source: source)
    }

    public var body: some View {
        Group {
            if feedbackDecision.showsFeedbackNavigation {
                button
            } else {
                toolbarPlaceholder
            }
        }
        .task(id: appLaunchSession.releaseControlPreparationID) {
            await loadFeedbackDecision()
        }
        .onReceive(NotificationCenter.default.publisher(for: ReleaseControlPreferenceStore.preferenceDidChangeNotification)) { _ in
            Task {
                await loadFeedbackDecision()
            }
        }
    }

    @MainActor
    private func loadFeedbackDecision() async {
        feedbackDecision = await releaseControlClient.activeDecision(for: .feedbackFeature)
    }

    private var button: some View {
        Button {
            if !feedbackPaneOpener.open(launchContext) {
                openWindow(id: FeedbackLaunchContext.windowID, value: launchContext)
            }
        } label: {
            FeedbackIdentityLabel("Provide Feedback")
        }
        .tint(FeedbackVisualIdentity.tint)
        .help("Provide Feedback")
    }

    private var toolbarPlaceholder: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

public extension View {
    func phoneFeedbackSheetToolbar(
        source: FeedbackLaunchSource = .toolbar
    ) -> some View {
        modifier(PhoneFeedbackSheetToolbarModifier(source: source))
    }
}

private struct PhoneFeedbackSheetToolbarModifier: ViewModifier {
    let source: FeedbackLaunchSource

    @Environment(\.releaseControlClient) private var releaseControlClient
    @EnvironmentObject private var appLaunchSession: AppLaunchSession

    @State private var feedbackDecision: ReleaseControlDecision = .disabled(.feedbackFeature)
    @State private var feedbackSheetContext: FeedbackLaunchContext?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if feedbackDecision.showsFeedbackNavigation && AppExperiencePlatform.isPhone {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            openFeedbackSheet()
                        } label: {
                            FeedbackIdentityLabel("Provide Feedback")
                        }
                        .tint(FeedbackVisualIdentity.tint)
                    }
                }
            }
            .sheet(item: $feedbackSheetContext) { context in
                NavigationStack {
                    FeedbackView(
                        launchContext: context,
                        showsPopOutButton: false,
                        launchSurface: .phoneSheet,
                        onSubmitted: { closeFeedbackSheet() }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .cancel) {
                                closeFeedbackSheet()
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .task(id: appLaunchSession.releaseControlPreparationID) {
                await loadFeedbackDecision()
            }
            .onReceive(NotificationCenter.default.publisher(for: ReleaseControlPreferenceStore.preferenceDidChangeNotification)) { _ in
                Task {
                    await loadFeedbackDecision()
                }
            }
    }

    @MainActor
    private func loadFeedbackDecision() async {
        feedbackDecision = await releaseControlClient.activeDecision(for: .feedbackFeature)
    }

    @MainActor
    private func openFeedbackSheet() {
        feedbackSheetContext = FeedbackLaunchContext(source: source)
    }

    @MainActor
    private func closeFeedbackSheet() {
        feedbackSheetContext = nil
    }
}
