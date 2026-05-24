import Foundation

public struct FeedbackIssueRenderer: Sendable {
    public init() { }

    public func payload(
        for draft: FeedbackDraft,
        owner: String,
        repo: String
    ) -> GitHubIssuePayload {
        GitHubIssuePayload(
            owner: owner,
            repo: repo,
            title: title(for: draft),
            body: body(for: draft),
            labels: [draft.category.issueLabel, "platform: shared", "priority: next"]
        )
    }

    public func title(for draft: FeedbackDraft) -> String {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return "[Feedback] \(draft.category.displayName)"
    }

    public func body(for draft: FeedbackDraft) -> String {
        let diagnostics = draft.diagnostics
        return """
        ## Feedback category
        \(draft.category.displayName)

        ## Summary
        \(valueOrPlaceholder(draft.summary))

        ## Steps to reproduce
        \(valueOrPlaceholder(draft.stepsToReproduce))

        ## Expected behavior
        \(valueOrPlaceholder(draft.expectedBehavior))

        ## Actual behavior
        \(valueOrPlaceholder(draft.actualBehavior))

        ## Additional context
        \(valueOrPlaceholder(draft.additionalContext))

        ## Safe diagnostics
        - App version: \(diagnostics.appVersion)
        - Build: \(diagnostics.buildNumber)
        - Platform: \(diagnostics.platform)
        - Feedback source: \(draft.source.displayName)
        - AI availability: \(diagnostics.aiAvailability)
        - Release control: \(diagnostics.releaseControl)
        - Launch context: \(diagnostics.launchContext ?? "Not provided")
        """
    }

    private func valueOrPlaceholder(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not provided." : trimmed
    }
}
