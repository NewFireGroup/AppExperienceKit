import Foundation
import SwiftData
import Testing

@testable import AppExperienceKit

@MainActor
struct FeedbackBehaviorTests {
    @Test
    func feedbackDraftStoreCreatesAndUpdatesLocalDrafts() throws {
        let store = try FeedbackDraftStore.inMemory()

        let draft = try store.createDraft(
            category: .bug,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        draft.title = "Crash while opening dashboard"
        draft.summary = "The app closes when I open the dashboard tab."
        try store.save(draft)

        let drafts = try store.fetchDrafts()

        #expect(drafts.count == 1)
        #expect(drafts[0].category == .bug)
        #expect(drafts[0].source == .manual)
        #expect(drafts[0].submissionState == .draft)
        #expect(drafts[0].title == "Crash while opening dashboard")
        #expect(drafts[0].diagnostics.platform == "iOS")
        #expect(drafts[0].diagnostics.aiAvailability == "available")
    }

    @Test
    func feedbackDraftStoreMarksSubmittedDraftsWithIssueURL() throws {
        let store = try FeedbackDraftStore.inMemory()
        let draft = try store.createDraft(
            category: .featureRequest,
            source: .aiAssisted,
            diagnostics: .testFixture(platform: "Mac Catalyst", aiAvailability: "unavailable")
        )

        try store.markSubmitted(
            draft,
            issueURL: URL(string: "https://github.com/ExampleOrg/ExampleApp/issues/123")!
        )

        #expect(draft.submissionState == .submitted)
        #expect(draft.githubIssueURL?.absoluteString == "https://github.com/ExampleOrg/ExampleApp/issues/123")
        #expect(draft.submittedAt != nil)
    }

    @Test
    func feedbackDraftStoreDeletesDrafts() throws {
        let store = try FeedbackDraftStore.inMemory()
        let draft = try store.createDraft(
            category: .bug,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )

        try store.deleteDraft(draft)

        #expect(try store.fetchDraft(id: draft.id) == nil)
        #expect(try store.fetchDrafts().isEmpty)
    }

    @Test
    func feedbackIssueRendererProducesTemplateAlignedMarkdown() {
        let draft = FeedbackDraft(
            category: .aiFeedback,
            source: .aiAssisted,
            diagnostics: .testFixture(platform: "iPadOS", aiAvailability: "available")
        )
        draft.title = "Improve feedback assistant"
        draft.summary = "The assistant should ask clearer follow-up questions."
        draft.stepsToReproduce = "Open Feedback and use AI Assist."
        draft.expectedBehavior = "The assistant asks one precise question at a time."
        draft.actualBehavior = "The assistant jumps to a draft too early."
        draft.additionalContext = "This came from an internal TestFlight run."

        let body = FeedbackIssueRenderer().body(for: draft)

        #expect(body.contains("## Feedback category\nAI feedback"))
        #expect(body.contains("## Summary\nThe assistant should ask clearer follow-up questions."))
        #expect(body.contains("## Steps to reproduce\nOpen Feedback and use AI Assist."))
        #expect(body.contains("## Expected behavior\nThe assistant asks one precise question at a time."))
        #expect(body.contains("## Actual behavior\nThe assistant jumps to a draft too early."))
        #expect(body.contains("## Additional context\nThis came from an internal TestFlight run."))
        #expect(body.contains("## Safe diagnostics"))
        #expect(body.contains("- Platform: iPadOS"))
        #expect(body.contains("- AI availability: available"))
        #expect(!body.contains("household"))
    }

    @Test
    func earlyAdopterSettingsToggleDoesNotDisconnectGitHub() {
        let suiteName = "FeedbackBehaviorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = InMemoryGitHubTokenStore(token: "token-123")
        let settings = EarlyAdopterSettingsStore(defaults: defaults, tokenStore: tokenStore)

        settings.setFeedbackEnabled(true)
        settings.setFeedbackEnabled(false)

        #expect(settings.isFeedbackEnabled == false)
        #expect(settings.githubConnectionState == .connected)
    }

    @Test
    func disconnectRemovesGitHubTokenWithoutChangingFeedbackToggle() {
        let suiteName = "FeedbackBehaviorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = InMemoryGitHubTokenStore(token: "token-123")
        let settings = EarlyAdopterSettingsStore(defaults: defaults, tokenStore: tokenStore)

        settings.setFeedbackEnabled(true)
        settings.disconnectGitHub()

        #expect(settings.isFeedbackEnabled)
        #expect(settings.githubConnectionState == .disconnected)
    }

    @Test
    func appleAssistSettingDefaultsOffAndDisablesWhenUnavailable() {
        let suiteName = "FeedbackBehaviorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = EarlyAdopterSettingsStore(defaults: defaults, tokenStore: InMemoryGitHubTokenStore())

        #expect(!settings.isAppleAssistEnabled)
        #expect(!settings.startsFeedbackWithAppleAssist)

        settings.setAppleAssistEnabled(true)
        settings.setStartsFeedbackWithAppleAssist(true)
        settings.disableAppleAssistIfUnavailable(.unavailable("Apple Intelligence is not enabled"))

        #expect(!settings.isAppleAssistEnabled)
        #expect(!settings.startsFeedbackWithAppleAssist)
    }

    @Test
    func feedbackAIAssistSettingsRequireOptimizelyAvailabilityAndUserPreference() {
        let enabledDecision = ReleaseControlDecision(
            key: .feedbackFeature,
            isEnabled: true,
            variables: ["ai_assist_enabled": "true"]
        )
        let disabledDecision = ReleaseControlDecision.disabled(.feedbackFeature)

        #expect(FeedbackAIAssistSettings.showsSettingsToggle(decision: enabledDecision))
        #expect(!FeedbackAIAssistSettings.showsSettingsToggle(decision: disabledDecision))
        #expect(FeedbackAIAssistSettings.showsToolbarButton(
            decision: enabledDecision,
            isUserEnabled: true,
            availability: .available
        ))
        #expect(!FeedbackAIAssistSettings.showsToolbarButton(
            decision: enabledDecision,
            isUserEnabled: false,
            availability: .available
        ))
        #expect(!FeedbackAIAssistSettings.showsToolbarButton(
            decision: enabledDecision,
            isUserEnabled: true,
            availability: .unavailable("Apple Intelligence is not enabled")
        ))
        #expect(!FeedbackAIAssistSettings.showsToolbarButton(
            decision: disabledDecision,
            isUserEnabled: true,
            availability: .available
        ))
        #expect(FeedbackAIAssistSettings.startsFeedbackWithAIAssist(
            decision: enabledDecision,
            isUserEnabled: true,
            isStartWithAssistEnabled: true,
            availability: .available,
            launchSurface: .phoneSheet,
            isEditingDraft: false,
            hasMeaningfulContent: false
        ))
        #expect(FeedbackAIAssistSettings.startsFeedbackWithAIAssist(
            decision: enabledDecision,
            isUserEnabled: true,
            isStartWithAssistEnabled: true,
            availability: .available,
            launchSurface: .splitPane,
            isEditingDraft: false,
            hasMeaningfulContent: false
        ))
        #expect(!FeedbackAIAssistSettings.startsFeedbackWithAIAssist(
            decision: enabledDecision,
            isUserEnabled: true,
            isStartWithAssistEnabled: true,
            availability: .available,
            launchSurface: .standaloneWindow,
            isEditingDraft: false,
            hasMeaningfulContent: false
        ))
        #expect(!FeedbackAIAssistSettings.startsFeedbackWithAIAssist(
            decision: enabledDecision,
            isUserEnabled: true,
            isStartWithAssistEnabled: true,
            availability: .available,
            launchSurface: .phoneSheet,
            isEditingDraft: true,
            hasMeaningfulContent: false
        ))
        #expect(!FeedbackAIAssistSettings.startsFeedbackWithAIAssist(
            decision: enabledDecision,
            isUserEnabled: true,
            isStartWithAssistEnabled: true,
            availability: .available,
            launchSurface: .phoneSheet,
            isEditingDraft: false,
            hasMeaningfulContent: true
        ))
    }

    @Test
    func feedbackAIAssistDisabledMessagesPointToAppleIntelligenceSettings() {
        #expect(FeedbackAIAssistSettings.disabledMessage(
            for: .unavailable("Apple Intelligence is not enabled"),
            platform: .iOS
        ) == "Apple Intelligence is currently disabled. To use this feature, open Settings > Apple Intelligence & Siri and turn on Apple Intelligence.")
        #expect(FeedbackAIAssistSettings.disabledMessage(
            for: .unavailable("Apple Intelligence is not enabled"),
            platform: .mac
        ) == "Apple Intelligence is currently disabled. To use this feature, open System Settings > Apple Intelligence & Siri and turn on Apple Intelligence.")
        #expect(FeedbackAIAssistSettings.disabledMessage(for: .available, platform: .iOS) == nil)
    }

    @Test
    func githubIssueClientCreatesIssuePayloadAndParsesIssueURL() async throws {
        let session = RecordingHTTPClient(
            responseData: Data(#"{"html_url":"https://github.com/ExampleOrg/ExampleApp/issues/123"}"#.utf8),
            statusCode: 201
        )
        let client = GitHubRESTIssueClient(httpClient: session)
        let payload = GitHubIssuePayload(
            owner: "ExampleOrg",
            repo: "ExampleApp",
            title: "Improve feedback assistant",
            body: "## Summary\nUseful feedback.",
            labels: ["type: feature"]
        )

        let issueURL = try await client.createIssue(payload, token: "github-token")

        #expect(issueURL.absoluteString == "https://github.com/ExampleOrg/ExampleApp/issues/123")
        #expect(session.lastRequest?.url?.absoluteString == "https://api.github.com/repos/ExampleOrg/ExampleApp/issues")
        #expect(session.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer github-token")
        #expect(session.lastRequestBodyString?.contains(#""title":"Improve feedback assistant""#) == true)
        #expect(session.lastRequestBodyString?.contains(#""labels":["type: feature"]"#) == true)
    }

    @Test
    func githubIssueClientKeepsAuthenticationFailuresExplicit() async {
        let session = RecordingHTTPClient(responseData: Data(#"{"message":"Bad credentials"}"#.utf8), statusCode: 401)
        let client = GitHubRESTIssueClient(httpClient: session)
        let payload = GitHubIssuePayload(owner: "ExampleOrg", repo: "ExampleApp", title: "T", body: "B", labels: [])

        await #expect(throws: GitHubIssueClientError.authenticationRequired) {
            _ = try await client.createIssue(payload, token: "expired")
        }
    }

    @Test
    func githubAuthViewModelStoresLinkedIdentityMetadataLocally() async throws {
        let defaults = try Self.defaults()
        let tokenStore = InMemoryGitHubTokenStore()
        let identityStore = AppIdentityStore(defaults: defaults)
        let session = SequencedHTTPClient(responses: [
            (
                Data(
                    #"{"device_code":"device-123","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#.utf8
                ),
                200
            ),
            (
                Data(#"{"access_token":"github-token"}"#.utf8),
                200
            )
        ])
        let viewModel = GitHubAuthViewModel(
            configuration: GitHubFeedbackConfiguration(clientID: "client-id", owner: "ExampleOrg", repo: "ExampleApp"),
            tokenStore: tokenStore,
            httpClient: session,
            identityClient: StaticGitHubIdentityClient(
                expectedToken: "github-token",
                identity: GitHubUserIdentity(id: 8752215, login: "daveboster")
            ),
            identityStore: identityStore
        )

        await viewModel.startAuthentication()
        await viewModel.completeAuthentication()

        #expect(tokenStore.loadToken() == "github-token")
        #expect(identityStore.authState == .githubLinked)
        #expect(identityStore.linkedGitHubIdentity?.id == 8752215)
        #expect(identityStore.linkedGitHubIdentity?.login == "daveboster")
        #expect(viewModel.connectionState == .connected)
    }

    @Test
    func githubFeedbackConfigurationRequiresHostRepositoryDefaults() throws {
        let bundle = try Self.bundle(info: [
            "CFBundleIdentifier": "dev.example.feedback-tests"
        ])

        let unconfigured = GitHubFeedbackConfiguration.mainBundle(bundle: bundle)
        let configured = GitHubFeedbackConfiguration.mainBundle(
            bundle: bundle,
            defaultOwner: "ExampleOrg",
            defaultRepo: "ExampleApp"
        )

        #expect(unconfigured.clientID == nil)
        #expect(unconfigured.owner.isEmpty)
        #expect(unconfigured.repo.isEmpty)
        #expect(!unconfigured.isIssueSubmissionConfigured)
        #expect(configured.owner == "ExampleOrg")
        #expect(configured.repo == "ExampleApp")
        #expect(configured.isIssueSubmissionConfigured)
    }

    @Test
    func aiCoordinatorFallsBackToManualWhenUnavailable() async throws {
        let coordinator = FeedbackAICoordinator(client: UnavailableFeedbackAIClient(reason: "Apple Intelligence is off"))

        let result = try await coordinator.assist(
            message: "The app crashes when I open Dashboard.",
            existingDraft: FeedbackDraft(
                category: .general,
                source: .manual,
                diagnostics: .testFixture(platform: "iOS", aiAvailability: "unavailable")
            )
        )

        #expect(result.mode == .manualFallback)
        #expect(result.reason == "Apple Intelligence is off")
    }

    @Test
    func feedbackAISuggestionParsesFencedJSONIntoDraftFields() {
        let draft = FeedbackDraft(
            category: .general,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        let content = """
        Here is a draft:

        ```json
        {
          "title": "Crash after opening Dashboard",
          "summary": "The app closes after I open the Dashboard screen.",
          "steps_to_reproduce": "Open the app, then tap Dashboard.",
          "expected_behavior": "Dashboard opens and stays visible.",
          "actual_behavior": "The app closes immediately.",
          "additional_context": "Started from the sidebar.",
          "category": "Bug"
        }
        ```
        """

        FeedbackAISuggestion.apply(content, to: draft)

        #expect(draft.category == .bug)
        #expect(draft.title == "Crash after opening Dashboard")
        #expect(draft.summary == "The app closes after I open the Dashboard screen.")
        #expect(draft.stepsToReproduce == "Open the app, then tap Dashboard.")
        #expect(draft.expectedBehavior == "Dashboard opens and stays visible.")
        #expect(draft.actualBehavior == "The app closes immediately.")
        #expect(draft.additionalContext == "Started from the sidebar.")
        #expect(!draft.summary.contains("```json"))
    }

    @Test
    func feedbackAIAssistResultPersistsForReloadedForms() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedbackBehaviorTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let storeURL = directoryURL.appendingPathComponent("feedback.sqlite")
        let store = try Self.feedbackDraftStore(url: storeURL)
        let draft = try store.createDraft(
            category: .general,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        draft.roughNote = "The feedback form does not update after AI Assist."
        try store.save(draft)

        FeedbackAISuggestion.apply(
            """
            {
              "title": "AI Assist does not update feedback form",
              "summary": "The AI Assist sheet finishes but the feedback form stays unchanged.",
              "category": "bug"
            }
            """,
            to: draft
        )

        let result = FeedbackAIAssistResult(mode: .aiAssisted, draft: draft)
        let snapshot = try FeedbackAIAssistResultApplier.apply(result, store: store)
        let reloadedStore = try Self.feedbackDraftStore(url: storeURL)
        let reloadedDraft = try #require(try reloadedStore.fetchDraft(id: draft.id))

        #expect(snapshot.source == .aiAssisted)
        #expect(snapshot.title == "AI Assist does not update feedback form")
        #expect(reloadedDraft.source == .aiAssisted)
        #expect(reloadedDraft.category == .bug)
        #expect(reloadedDraft.title == "AI Assist does not update feedback form")
        #expect(reloadedDraft.summary == "The AI Assist sheet finishes but the feedback form stays unchanged.")
        #expect(reloadedDraft.roughNote == "The feedback form does not update after AI Assist.")
    }

    @Test
    func feedbackDraftStoreResetRemovesLocalStoreAndAllowsFreshStart() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedbackBehaviorTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let storeURL = directoryURL.appendingPathComponent("feedback.sqlite")
        let store = try Self.feedbackDraftStore(url: storeURL)
        let draft = try store.createDraft(
            category: .bug,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        draft.title = "Feedback store needs reset"
        try store.save(draft)
        let sidecarURL = directoryURL.appendingPathComponent("feedback.sqlite-wal")
        try Data("sidecar".utf8).write(to: sidecarURL)

        try FeedbackDraftStore.resetStore(at: directoryURL)

        #expect(FileManager.default.fileExists(atPath: directoryURL.path))
        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
        #expect(!FileManager.default.fileExists(atPath: sidecarURL.path))

        let freshStore = try Self.feedbackDraftStore(url: storeURL)
        #expect(try freshStore.fetchDrafts().isEmpty)
    }

    @Test
    func feedbackAIAssistApplyCreatesDraftAndReturnsUpdatedFormSnapshot() async throws {
        let store = try FeedbackDraftStore.inMemory()
        let update = try await FeedbackAIAssistSession.apply(
            message: "AI Assist finishes but the feedback form does not update.",
            snapshot: FeedbackFormSnapshot(
                category: .general,
                source: .manual,
                roughNote: "AI Assist finishes but the feedback form does not update."
            ),
            currentDraft: nil,
            store: store,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available"),
            client: StaticFeedbackAIClient(content: """
            {
              "title": "AI Assist does not update form",
              "summary": "After tapping Apply, the sheet stays up and the feedback form stays unchanged.",
              "category": "bug"
            }
            """)
        )
        let reloadedDraft = try #require(try store.fetchDraft(id: update.draft.id))

        #expect(update.snapshot.source == .aiAssisted)
        #expect(update.snapshot.category == .bug)
        #expect(update.snapshot.title == "AI Assist does not update form")
        #expect(update.snapshot.summary == "After tapping Apply, the sheet stays up and the feedback form stays unchanged.")
        #expect(update.snapshot.roughNote == "AI Assist finishes but the feedback form does not update.")
        #expect(reloadedDraft.source == .aiAssisted)
        #expect(reloadedDraft.title == "AI Assist does not update form")
    }

    @Test
    func feedbackAIAssistApplyPropagatesCancellationWithoutApplyingResult() async throws {
        let store = try FeedbackDraftStore.inMemory()
        await #expect(throws: CancellationError.self) {
            try await FeedbackAIAssistSession.apply(
                message: "Cancel while AI Assist is still working.",
                snapshot: FeedbackFormSnapshot(
                    category: .general,
                    source: .manual,
                    roughNote: "Cancel while AI Assist is still working."
                ),
                currentDraft: nil,
                store: store,
                diagnostics: .testFixture(platform: "Mac Catalyst", aiAvailability: "available"),
                client: CancellationFeedbackAIClient()
            )
        }

        let drafts = try store.fetchDrafts()
        #expect(drafts.allSatisfy { $0.source != .aiAssisted })
        #expect(drafts.allSatisfy { $0.title.isEmpty })
    }

    @Test
    func feedbackSubmitActionsKeepLocalSubmitPrimary() {
        #expect(FeedbackSubmitActions.primaryTitle == "Submit")
        #expect(FeedbackSubmitActions.availableActions(githubConnectionState: .disconnected) == [.local])
        #expect(FeedbackSubmitActions.availableActions(githubConnectionState: .connected) == [.local, .github])
        #expect(FeedbackSubmitActions.availableActions(
            githubConnectionState: .connected,
            allowsGitHubSubmission: false
        ) == [.local])
    }

    @Test
    func feedbackSubmitOutcomeClosesFormOnlyAfterSuccessfulSubmission() {
        #expect(FeedbackSubmitOutcome.submitted.closesForm)
        #expect(!FeedbackSubmitOutcome.savedPendingAuthentication.closesForm)
        #expect(!FeedbackSubmitOutcome.failed.closesForm)
    }

    @Test @MainActor
    func feedbackSubmitPresentationClosesOnlyAfterSuccessfulSubmission() {
        var closeCount = 0
        let presentation = FeedbackSubmitPresentation {
            closeCount += 1
        }

        presentation.handle(.savedPendingAuthentication)
        presentation.handle(.failed)
        #expect(closeCount == 0)

        presentation.handle(.submitted)
        #expect(closeCount == 1)
    }

    @Test
    func feedbackTelemetryUsesSnakeCaseValuesForOptimizelyProperties() {
        #expect(FeedbackCategory.bug.telemetryValue == "bug")
        #expect(FeedbackCategory.featureRequest.telemetryValue == "feature_request")
        #expect(FeedbackCategory.aiFeedback.telemetryValue == "ai_feedback")
        #expect(FeedbackCategory.general.telemetryValue == "general")
        #expect(FeedbackDraftSource.manual.telemetryValue == "manual")
        #expect(FeedbackDraftSource.aiAssisted.telemetryValue == "ai_assisted")
        #expect(FeedbackSubmitAction.local.telemetryDestination == "local")
        #expect(FeedbackSubmitAction.github.telemetryDestination == "github")
        #expect(FeedbackAIAssistMode.aiAssisted.telemetryResult == "ai_assisted")
        #expect(FeedbackAIAssistMode.manualFallback.telemetryResult == "manual_fallback")
    }

    @Test
    func feedbackTelemetryTracksStartedOnceAndAbandonsOnlyUnsubmittedForms() {
        var telemetry = FeedbackTelemetryState()
        let decision = ReleaseControlDecision(
            key: .feedbackFeature,
            isEnabled: true,
            variationKey: "variant_a"
        )
        let launchContext = FeedbackLaunchContext(source: .cashflowSummary)

        #expect(telemetry.featureOpenedEvent(launchContext: launchContext, decision: decision) == .feedbackFeatureOpened(
            launchSource: "cashflow_summary",
            variationKey: "variant_a"
        ))
        #expect(telemetry.featureOpenedEvent(launchContext: launchContext, decision: decision) == nil)
        #expect(telemetry.formStartedEvent(
            category: .bug,
            source: .manual,
            launchContext: launchContext,
            decision: decision
        ) == .feedbackFormStarted(
            category: "bug",
            source: "manual",
            launchSource: "cashflow_summary",
            variationKey: "variant_a"
        ))
        #expect(telemetry.formStartedEvent(
            category: .aiFeedback,
            source: .aiAssisted,
            launchContext: launchContext,
            decision: decision
        ) == nil)
        #expect(telemetry.aiAssistOpenedEvent(
            category: .aiFeedback,
            source: .manual,
            launchContext: launchContext,
            decision: decision
        ) == .feedbackAIAssistOpened(
            category: "ai_feedback",
            source: "manual",
            launchSource: "cashflow_summary",
            variationKey: "variant_a"
        ))
        #expect(telemetry.aiAssistUsedEvent(
            category: .aiFeedback,
            source: .aiAssisted,
            result: "ai_assisted",
            launchContext: launchContext,
            decision: decision
        ) == .feedbackAIAssistUsed(
            category: "ai_feedback",
            source: "ai_assisted",
            aiResult: "ai_assisted",
            launchSource: "cashflow_summary",
            variationKey: "variant_a"
        ))
        #expect(telemetry.aiAssistCanceledEvent(
            category: .aiFeedback,
            source: .manual,
            launchContext: launchContext,
            decision: decision
        ) == .feedbackAIAssistCanceled(
            category: "ai_feedback",
            source: "manual",
            launchSource: "cashflow_summary",
            variationKey: "variant_a"
        ))
        #expect(telemetry.formAbandonedEvent(
            category: .bug,
            source: .manual,
            launchContext: launchContext,
            decision: decision
        ) == .feedbackFormAbandoned(
            category: "bug",
            source: "manual",
            launchSource: "cashflow_summary",
            variationKey: "variant_a"
        ))
        #expect(telemetry.formAbandonedEvent(
            category: .bug,
            source: .manual,
            launchContext: launchContext,
            decision: decision
        ) == nil)
    }

    @Test
    func feedbackTelemetryDoesNotAbandonCompletedForms() {
        var telemetry = FeedbackTelemetryState()
        let decision = ReleaseControlDecision(
            key: .feedbackFeature,
            isEnabled: true,
            variationKey: "variant_a"
        )
        let launchContext = FeedbackLaunchContext(source: .settings)

        _ = telemetry.formStartedEvent(
            category: .featureRequest,
            source: .manual,
            launchContext: launchContext,
            decision: decision
        )

        #expect(telemetry.formSubmittedEvent(
            category: .featureRequest,
            source: .manual,
            action: .local,
            launchContext: launchContext,
            decision: decision
        ) == .feedbackSubmitted(
            category: "feature_request",
            source: "manual",
            destination: "local",
            launchSource: "settings",
            variationKey: "variant_a"
        ))
        #expect(telemetry.formAbandonedEvent(
            category: .featureRequest,
            source: .manual,
            launchContext: launchContext,
            decision: decision
        ) == nil)
    }

    @Test
    func feedbackLaunchContextProvidesStableWindowValuesAndDisplayNames() {
        let context = FeedbackLaunchContext(source: .cashflowSummary)
        let withDraft = context.withDraftID(UUID(uuidString: "F4E25E34-88C7-4A1D-8E8A-17F00F184C64")!)

        #expect(FeedbackLaunchContext.windowID == "feedback")
        #expect(context.displayName == "Cashflow Summary")
        #expect(context.diagnosticsValue == "cashflow_summary")
        #expect(withDraft.draftID?.uuidString == "F4E25E34-88C7-4A1D-8E8A-17F00F184C64")
        #expect(withDraft.source == .cashflowSummary)
    }

    @Test
    func feedbackDiagnosticsAndIssueBodyIncludeLaunchContext() {
        let diagnostics = FeedbackDiagnostics.testFixture(
            platform: "iOS",
            aiAvailability: "available",
            launchContext: "cashflow_summary"
        )
        let draft = FeedbackDraft(
            category: .general,
            source: .manual,
            diagnostics: diagnostics
        )

        let body = FeedbackIssueRenderer().body(for: draft)

        #expect(draft.diagnostics.launchContext == "cashflow_summary")
        #expect(body.contains("- Launch context: cashflow_summary"))
    }

    @Test
    func feedbackFormSnapshotDetectsMeaningfulContentAndAppliesToDraft() {
        let store = try! FeedbackDraftStore.inMemory()
        let draft = try! store.createDraft(
            category: .general,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        let empty = FeedbackFormSnapshot()
        let filled = FeedbackFormSnapshot(
            category: .bug,
            source: .aiAssisted,
            title: "Crash on summary",
            summary: "Dashboard summary closes.",
            additionalContext: "Launched from dashboard summary.",
            roughNote: "I tapped the summary tab and the app closed."
        )

        #expect(!empty.hasMeaningfulContent)
        #expect(filled.hasMeaningfulContent)

        filled.apply(to: draft)

        #expect(draft.category == .bug)
        #expect(draft.source == .aiAssisted)
        #expect(draft.title == "Crash on summary")
        #expect(draft.summary == "Dashboard summary closes.")
        #expect(draft.additionalContext == "Launched from dashboard summary.")
        #expect(draft.roughNote == "I tapped the summary tab and the app closed.")
    }

    @Test
    func feedbackDraftStoreFetchesSavedDraftForPopOutWindows() throws {
        let store = try FeedbackDraftStore.inMemory()
        let draft = try store.createDraft(
            category: .bug,
            source: .manual,
            diagnostics: .testFixture(platform: "iPadOS", aiAvailability: "available")
        )
        draft.title = "Keep this draft"
        try store.save(draft)

        let fetched = try store.fetchDraft(id: draft.id)

        #expect(fetched?.id == draft.id)
        #expect(fetched?.title == "Keep this draft")
    }

    @Test
    func feedbackDraftStoreFetchesLatestRestorableDraftForNavigationReturn() throws {
        let store = try FeedbackDraftStore.inMemory()
        let olderDraft = try store.createDraft(
            category: .bug,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        olderDraft.title = "Older draft"
        olderDraft.modifiedAt = Date(timeIntervalSince1970: 100)

        let submittedDraft = try store.createDraft(
            category: .featureRequest,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        submittedDraft.title = "Already submitted"
        try store.markSubmitted(submittedDraft, issueURL: nil)
        submittedDraft.modifiedAt = Date(timeIntervalSince1970: 300)

        let latestDraft = try store.createDraft(
            category: .general,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        latestDraft.summary = "Restore this draft when the form opens again."
        latestDraft.modifiedAt = Date(timeIntervalSince1970: 200)

        let fetched = try store.fetchLatestRestorableDraft()

        #expect(fetched?.id == latestDraft.id)
        #expect(fetched?.summary == "Restore this draft when the form opens again.")
    }

    @Test
    func feedbackDraftStoreFetchesSubmittedFeedbackForMyFeedbackList() throws {
        let store = try FeedbackDraftStore.inMemory()
        let draft = try store.createDraft(
            category: .bug,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        draft.title = "Unsubmitted draft"
        try store.save(draft)

        let olderSubmitted = try store.createDraft(
            category: .featureRequest,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        olderSubmitted.title = "Older submitted feedback"
        try store.markSubmitted(olderSubmitted, issueURL: nil)
        olderSubmitted.submittedAt = Date(timeIntervalSince1970: 100)
        try store.save(olderSubmitted)

        let latestSubmitted = try store.createDraft(
            category: .aiFeedback,
            source: .aiAssisted,
            diagnostics: .testFixture(platform: "iPadOS", aiAvailability: "available")
        )
        latestSubmitted.title = "Latest submitted feedback"
        try store.markSubmitted(latestSubmitted, issueURL: URL(string: "https://github.com/ExampleOrg/ExampleApp/issues/456")!)
        latestSubmitted.submittedAt = Date(timeIntervalSince1970: 200)
        try store.save(latestSubmitted)

        let submittedFeedback = try store.fetchSubmittedFeedback()

        #expect(submittedFeedback.map(\.title) == ["Latest submitted feedback", "Older submitted feedback"])
    }

    @Test
    func feedbackDraftStoreGroupsActiveArchivedAndRecentlyDeletedFeedback() throws {
        let store = try FeedbackDraftStore.inMemory()
        let active = try store.createDraft(
            category: .general,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        active.title = "Active feedback"
        active.modifiedAt = Date(timeIntervalSince1970: 100)
        try store.save(active)

        let archived = try store.createDraft(
            category: .featureRequest,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        archived.title = "Archived feedback"
        try store.archive(archived)
        archived.archivedAt = Date(timeIntervalSince1970: 200)
        try store.save(archived)

        let deleted = try store.createDraft(
            category: .bug,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        deleted.title = "Deleted feedback"
        try store.softDelete(deleted)
        deleted.deletedAt = Date(timeIntervalSince1970: 300)
        try store.save(deleted)

        #expect(try store.fetchActiveFeedback().map(\.title) == ["Active feedback"])
        #expect(try store.fetchArchivedFeedback().map(\.title) == ["Archived feedback"])
        #expect(try store.fetchRecentlyDeletedFeedback().map(\.title) == ["Deleted feedback"])
    }

    @Test
    func feedbackDraftStoreRestoresArchivedAndRecentlyDeletedFeedback() throws {
        let store = try FeedbackDraftStore.inMemory()
        let draft = try store.createDraft(
            category: .bug,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        draft.title = "Recoverable feedback"

        try store.archive(draft)
        #expect(draft.archivedAt != nil)
        #expect(try store.fetchActiveFeedback().isEmpty)

        try store.unarchive(draft)
        #expect(draft.archivedAt == nil)
        #expect(try store.fetchActiveFeedback().map(\.id) == [draft.id])

        try store.softDelete(draft)
        #expect(draft.deletedAt != nil)
        #expect(draft.archivedAt == nil)
        #expect(try store.fetchActiveFeedback().isEmpty)

        try store.restore(draft)
        #expect(draft.deletedAt == nil)
        #expect(try store.fetchActiveFeedback().map(\.id) == [draft.id])
    }

    @Test
    func feedbackExportRendererProducesMarkdownForLocalAndSharedExports() throws {
        let draft = FeedbackDraft(
            category: .bug,
            source: .manual,
            diagnostics: .testFixture(platform: "iOS", aiAvailability: "available")
        )
        draft.title = "Crash opening feedback"
        draft.summary = "The app closed after I opened the feedback form."
        draft.submissionState = .submitted
        draft.submittedAt = Date(timeIntervalSince1970: 0)

        let markdown = FeedbackExportRenderer().markdown(for: draft)

        #expect(markdown.contains("# Crash opening feedback"))
        #expect(markdown.contains("Submission destination: Local"))
        #expect(markdown.contains("## Summary\nThe app closed after I opened the feedback form."))
        #expect(markdown.contains("## Safe diagnostics"))
    }

    private static func defaults() throws -> UserDefaults {
        let suiteName = "FeedbackBehaviorTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
    }

    private static func bundle(info: [String: String]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedbackBehaviorTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        #expect((info as NSDictionary).write(to: infoURL, atomically: true))
        return try #require(Bundle(url: bundleURL))
    }

    private static func feedbackDraftStore(url: URL) throws -> FeedbackDraftStore {
        let configuration = ModelConfiguration(
            schema: Schema(FeedbackSchema.all),
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: Schema(FeedbackSchema.all),
            configurations: configuration
        )
        return FeedbackDraftStore(container: container)
    }
}

private final class InMemoryGitHubTokenStore: GitHubTokenStore {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func loadToken() -> String? {
        token
    }

    func saveToken(_ token: String) {
        self.token = token
    }

    func deleteToken() {
        token = nil
    }
}

private final class RecordingHTTPClient: HTTPClient {
    private let responseData: Data
    private let statusCode: Int

    private(set) var lastRequest: URLRequest?
    private(set) var lastRequestBodyString: String?

    init(responseData: Data, statusCode: Int) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        if let body = request.httpBody {
            lastRequestBodyString = String(data: body, encoding: .utf8)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

private final class SequencedHTTPClient: HTTPClient {
    private var responses: [(Data, Int)]

    init(responses: [(Data, Int)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }

        let (data, statusCode) = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private struct StaticGitHubIdentityClient: GitHubIdentityClient {
    let expectedToken: String
    let identity: GitHubUserIdentity

    func fetchAuthenticatedUser(token: String) async throws -> GitHubUserIdentity {
        guard token == expectedToken else {
            throw GitHubIdentityClientError.authenticationRequired
        }

        return identity
    }
}

private struct UnavailableFeedbackAIClient: FeedbackAIClient {
    let reason: String

    func availability() -> FeedbackAIAvailability {
        .unavailable(reason)
    }

    func assist(message: String, existingDraft: FeedbackDraft) async throws -> FeedbackAIAssistResult {
        FeedbackAIAssistResult(mode: .manualFallback, draft: existingDraft, reason: reason)
    }
}

private struct StaticFeedbackAIClient: FeedbackAIClient {
    let content: String

    func availability() -> FeedbackAIAvailability {
        .available
    }

    func assist(message: String, existingDraft: FeedbackDraft) async throws -> FeedbackAIAssistResult {
        FeedbackAISuggestion.apply(content, to: existingDraft)
        return FeedbackAIAssistResult(mode: .aiAssisted, draft: existingDraft)
    }
}

private struct CancellationFeedbackAIClient: FeedbackAIClient {
    func availability() -> FeedbackAIAvailability {
        .available
    }

    func assist(message: String, existingDraft: FeedbackDraft) async throws -> FeedbackAIAssistResult {
        throw CancellationError()
    }
}

private extension FeedbackDiagnostics {
    static func testFixture(
        platform: String,
        aiAvailability: String,
        launchContext: String? = nil
    ) -> FeedbackDiagnostics {
        FeedbackDiagnostics(
            appVersion: "1.0.2",
            buildNumber: "102",
            platform: platform,
            aiAvailability: aiAvailability,
            releaseControl: "feedback_feature:on",
            launchContext: launchContext
        )
    }
}
