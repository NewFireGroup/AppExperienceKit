import Foundation
import Testing

@testable import AppExperienceKit

@MainActor
struct FeedbackPackageTests {
    @Test
    func appSettingsDestinationsSeparateAccountSecurityAndProductFeedback() {
        #expect(AppSettingsDestination.allCases == [
            .featurePreviews,
            .accountSecurity,
            .productFeedback
        ])
        #expect(AppSettingsDestination.accountSecurity.title == "Account & Security")
        #expect(AppSettingsDestination.productFeedback.title == "Product Feedback")
    }

    @Test
    func feedbackPaneStateOpensReplacesAndClosesContext() {
        var state = FeedbackPaneState()
        let cashflowContext = FeedbackLaunchContext(source: .cashflowSummary)
        let settingsContext = FeedbackLaunchContext(source: .settings)

        #expect(!state.isPresented)
        #expect(state.launchContext == nil)
        #expect(state.columnVisibility == .doubleColumn)

        state.open(cashflowContext)

        #expect(state.isPresented)
        #expect(state.launchContext == cashflowContext)
        #expect(state.columnVisibility == .doubleColumn)

        state.open(settingsContext)

        #expect(state.isPresented)
        #expect(state.launchContext == settingsContext)

        state.close()

        #expect(!state.isPresented)
        #expect(state.launchContext == nil)
        #expect(state.columnVisibility == .doubleColumn)
    }

    @Test
    func feedbackPaneStatePrefersMinimumAllowedColumnWidth() {
        let width = FeedbackPaneState.feedbackColumnWidth

        #expect(width.minimum == FeedbackPaneColumnWidth.compactPhoneWidth)
        #expect(width.ideal == width.minimum)
        #expect(width.maximum == width.minimum)
    }

    @Test
    func feedbackIssueRendererProducesTemplateAlignedMarkdown() {
        let draft = FeedbackDraft(
            category: .aiFeedback,
            source: .aiAssisted,
            diagnostics: FeedbackDiagnostics(
                appVersion: "1.0.15",
                buildNumber: "42",
                platform: "iPadOS",
                aiAvailability: "available",
                releaseControl: "enabled",
                launchContext: "feature_previews"
            )
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
        #expect(body.contains("- App version: 1.0.15"))
        #expect(body.contains("- Build: 42"))
        #expect(body.contains("- Platform: iPadOS"))
        #expect(body.contains("- Feedback source: AI assisted"))
        #expect(body.contains("- Launch context: feature_previews"))
        #expect(!body.contains("household"))
    }

    @Test
    func feedbackSubmitActionsRequireConfiguredGitHubRepository() {
        #expect(FeedbackSubmitActions.primaryTitle == "Submit")
        #expect(FeedbackSubmitActions.availableActions(githubConnectionState: .disconnected) == [.local])
        #expect(FeedbackSubmitActions.availableActions(githubConnectionState: .connected) == [.local, .github])
        #expect(FeedbackSubmitActions.availableActions(
            githubConnectionState: .connected,
            allowsGitHubSubmission: false
        ) == [.local])
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

    private static func bundle(info: [String: String]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedbackPackageTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        #expect((info as NSDictionary).write(to: infoURL, atomically: true))
        return try #require(Bundle(url: bundleURL))
    }
}
