import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

public enum FeedbackCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case bug
    case featureRequest
    case aiFeedback
    case general

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bug:
            return "Bug"
        case .featureRequest:
            return "Feature request"
        case .aiFeedback:
            return "AI feedback"
        case .general:
            return "General feedback"
        }
    }

    public var issueLabel: String {
        switch self {
        case .bug:
            return "type: bug"
        case .featureRequest, .aiFeedback, .general:
            return "type: feature"
        }
    }

    public var telemetryValue: String {
        switch self {
        case .bug:
            return "bug"
        case .featureRequest:
            return "feature_request"
        case .aiFeedback:
            return "ai_feedback"
        case .general:
            return "general"
        }
    }

}

public enum FeedbackDraftSource: String, Codable, Sendable {
    case manual
    case aiAssisted

    public var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .aiAssisted:
            return "AI assisted"
        }
    }

    public var telemetryValue: String {
        switch self {
        case .manual:
            return "manual"
        case .aiAssisted:
            return "ai_assisted"
        }
    }

}

public enum FeedbackSubmissionState: String, Codable, Sendable {
    case draft
    case failed
    case submitted
}

public enum FeedbackSubmitAction: Hashable, Sendable {
    case local
    case github

    public var title: String {
        switch self {
        case .local:
            return FeedbackSubmitActions.primaryTitle
        case .github:
            return "Submit to GitHub"
        }
    }

    public var systemImage: String {
        switch self {
        case .local:
            return "checkmark"
        case .github:
            return "paperplane"
        }
    }

    public var telemetryDestination: String {
        switch self {
        case .local:
            return "local"
        case .github:
            return "github"
        }
    }
}

public enum FeedbackSubmitActions {
    public static let primaryTitle = "Submit"

    public static func availableActions(
        githubConnectionState: GitHubConnectionState,
        allowsGitHubSubmission: Bool = true
    ) -> [FeedbackSubmitAction] {
        if githubConnectionState == .connected && allowsGitHubSubmission {
            return [.local, .github]
        }

        return [.local]
    }
}

enum FeedbackSubmitOutcome: Sendable {
    case submitted
    case savedPendingAuthentication
    case failed

    var closesForm: Bool {
        switch self {
        case .submitted:
            return true
        case .savedPendingAuthentication, .failed:
            return false
        }
    }
}

struct FeedbackSubmitPresentation {
    private let close: @MainActor () -> Void

    init(close: @escaping @MainActor () -> Void) {
        self.close = close
    }

    @MainActor
    func handle(_ outcome: FeedbackSubmitOutcome) {
        guard outcome.closesForm else { return }
        close()
    }
}

public enum FeedbackLaunchSource: String, Codable, Hashable, CaseIterable, Sendable {
    case feedbackNavigation = "feedback_navigation"
    case toolbar = "toolbar"
    case overview = "overview"
    case households = "households"
    case editHousehold = "edit_household"
    case cashflowSummary = "cashflow_summary"
    case cashflowItems = "cashflow_items"
    case cashflowReports = "cashflow_reports"
    case cashflowRunningBalance = "cashflow_running_balance"
    case planningAreasOfFocus = "planning_areas_of_focus"
    case planningActionPlan = "planning_action_plan"
    case planningAssumptions = "planning_assumptions"
    case planningSamplePlan = "planning_sample_plan"
    case featurePreviews = "feature_previews"
    case settings = "settings"
    case about = "about"

    public var displayName: String {
        switch self {
        case .feedbackNavigation:
            return "Feedback Navigation"
        case .toolbar:
            return "Toolbar"
        case .overview:
            return "Overview"
        case .households:
            return "Households"
        case .editHousehold:
            return "Edit Household"
        case .cashflowSummary:
            return "Cashflow Summary"
        case .cashflowItems:
            return "Cashflow Items"
        case .cashflowReports:
            return "Cashflow Reports"
        case .cashflowRunningBalance:
            return "Cashflow Running Balance"
        case .planningAreasOfFocus:
            return "Planning Areas of Focus"
        case .planningActionPlan:
            return "Planning Action Plan"
        case .planningAssumptions:
            return "Planning Assumptions"
        case .planningSamplePlan:
            return "Planning Sample Plan"
        case .featurePreviews:
            return "Feature Previews"
        case .settings:
            return "Settings"
        case .about:
            return "About"
        }
    }

    public var telemetryValue: String {
        rawValue
    }
}

public struct FeedbackLaunchContext: Codable, Hashable, Identifiable, Sendable {
    public static let windowID = "feedback"

    public var source: FeedbackLaunchSource
    public var draftID: UUID?

    public init(source: FeedbackLaunchSource = .feedbackNavigation, draftID: UUID? = nil) {
        self.source = source
        self.draftID = draftID
    }

    public var id: String {
        [source.rawValue, draftID?.uuidString]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    public var displayName: String {
        source.displayName
    }

    public var diagnosticsValue: String {
        source.rawValue
    }

    public func withDraftID(_ draftID: UUID) -> FeedbackLaunchContext {
        FeedbackLaunchContext(source: source, draftID: draftID)
    }
}

public struct FeedbackFormSnapshot: Equatable, Sendable {
    public var category: FeedbackCategory
    public var source: FeedbackDraftSource
    public var title: String
    public var summary: String
    public var stepsToReproduce: String
    public var expectedBehavior: String
    public var actualBehavior: String
    public var additionalContext: String
    public var roughNote: String

    public init(
        category: FeedbackCategory = .general,
        source: FeedbackDraftSource = .manual,
        title: String = "",
        summary: String = "",
        stepsToReproduce: String = "",
        expectedBehavior: String = "",
        actualBehavior: String = "",
        additionalContext: String = "",
        roughNote: String = ""
    ) {
        self.category = category
        self.source = source
        self.title = title
        self.summary = summary
        self.stepsToReproduce = stepsToReproduce
        self.expectedBehavior = expectedBehavior
        self.actualBehavior = actualBehavior
        self.additionalContext = additionalContext
        self.roughNote = roughNote
    }

    public init(draft: FeedbackDraft) {
        self.init(
            category: draft.category,
            source: draft.source,
            title: draft.title,
            summary: draft.summary,
            stepsToReproduce: draft.stepsToReproduce,
            expectedBehavior: draft.expectedBehavior,
            actualBehavior: draft.actualBehavior,
            additionalContext: draft.additionalContext,
            roughNote: draft.roughNote
        )
    }

    public var hasMeaningfulContent: Bool {
        category != .general ||
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !stepsToReproduce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !expectedBehavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !actualBehavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !additionalContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !roughNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func apply(to draft: FeedbackDraft) {
        draft.category = category
        draft.source = source
        draft.title = title
        draft.summary = summary
        draft.stepsToReproduce = stepsToReproduce
        draft.expectedBehavior = expectedBehavior
        draft.actualBehavior = actualBehavior
        draft.additionalContext = additionalContext
        draft.roughNote = roughNote
    }
}

public struct FeedbackTelemetryState: Equatable, Sendable {
    private var hasTrackedFeatureOpened = false
    private var hasTrackedFormStarted = false
    private var hasTrackedFormSubmitted = false
    private var hasTrackedFormAbandoned = false

    public init() {
    }

    public mutating func featureOpenedEvent(
        launchContext: FeedbackLaunchContext,
        decision: ReleaseControlDecision
    ) -> ReleaseControlEvent? {
        guard decision.isEnabled, !hasTrackedFeatureOpened else { return nil }
        hasTrackedFeatureOpened = true
        return .feedbackFeatureOpened(
            launchSource: launchContext.source.telemetryValue,
            variationKey: decision.variationKey
        )
    }

    public mutating func formStartedEvent(
        category: FeedbackCategory,
        source: FeedbackDraftSource,
        launchContext: FeedbackLaunchContext,
        decision: ReleaseControlDecision
    ) -> ReleaseControlEvent? {
        guard !hasTrackedFormStarted else { return nil }
        hasTrackedFormStarted = true
        return .feedbackFormStarted(
            category: category.telemetryValue,
            source: source.telemetryValue,
            launchSource: launchContext.source.telemetryValue,
            variationKey: decision.variationKey
        )
    }

    public mutating func aiAssistUsedEvent(
        category: FeedbackCategory,
        source: FeedbackDraftSource,
        result: String,
        launchContext: FeedbackLaunchContext,
        decision: ReleaseControlDecision
    ) -> ReleaseControlEvent {
        .feedbackAIAssistUsed(
            category: category.telemetryValue,
            source: source.telemetryValue,
            aiResult: result,
            launchSource: launchContext.source.telemetryValue,
            variationKey: decision.variationKey
        )
    }

    public mutating func aiAssistOpenedEvent(
        category: FeedbackCategory,
        source: FeedbackDraftSource,
        launchContext: FeedbackLaunchContext,
        decision: ReleaseControlDecision
    ) -> ReleaseControlEvent {
        .feedbackAIAssistOpened(
            category: category.telemetryValue,
            source: source.telemetryValue,
            launchSource: launchContext.source.telemetryValue,
            variationKey: decision.variationKey
        )
    }

    public mutating func aiAssistCanceledEvent(
        category: FeedbackCategory,
        source: FeedbackDraftSource,
        launchContext: FeedbackLaunchContext,
        decision: ReleaseControlDecision
    ) -> ReleaseControlEvent {
        .feedbackAIAssistCanceled(
            category: category.telemetryValue,
            source: source.telemetryValue,
            launchSource: launchContext.source.telemetryValue,
            variationKey: decision.variationKey
        )
    }

    public mutating func formSubmittedEvent(
        category: FeedbackCategory,
        source: FeedbackDraftSource,
        action: FeedbackSubmitAction,
        launchContext: FeedbackLaunchContext,
        decision: ReleaseControlDecision
    ) -> ReleaseControlEvent? {
        guard !hasTrackedFormSubmitted else { return nil }
        hasTrackedFormSubmitted = true
        return .feedbackSubmitted(
            category: category.telemetryValue,
            source: source.telemetryValue,
            destination: action.telemetryDestination,
            launchSource: launchContext.source.telemetryValue,
            variationKey: decision.variationKey
        )
    }

    public mutating func formAbandonedEvent(
        category: FeedbackCategory,
        source: FeedbackDraftSource,
        launchContext: FeedbackLaunchContext,
        decision: ReleaseControlDecision
    ) -> ReleaseControlEvent? {
        guard hasTrackedFormStarted, !hasTrackedFormSubmitted, !hasTrackedFormAbandoned else { return nil }
        hasTrackedFormAbandoned = true
        return .feedbackFormAbandoned(
            category: category.telemetryValue,
            source: source.telemetryValue,
            launchSource: launchContext.source.telemetryValue,
            variationKey: decision.variationKey
        )
    }
}

public struct FeedbackDiagnostics: Codable, Equatable, Sendable {
    public var appVersion: String
    public var buildNumber: String
    public var platform: String
    public var aiAvailability: String
    public var releaseControl: String
    public var launchContext: String?

    public init(
        appVersion: String,
        buildNumber: String,
        platform: String,
        aiAvailability: String,
        releaseControl: String,
        launchContext: String? = nil
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.platform = platform
        self.aiAvailability = aiAvailability
        self.releaseControl = releaseControl
        self.launchContext = launchContext
    }

    public static func current(
        aiAvailability: String,
        releaseControl: String,
        launchContext: FeedbackLaunchContext = FeedbackLaunchContext(),
        bundle: Bundle = .main
    ) -> FeedbackDiagnostics {
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        return FeedbackDiagnostics(
            appVersion: appVersion,
            buildNumber: buildNumber,
            platform: Self.platformName,
            aiAvailability: aiAvailability,
            releaseControl: releaseControl,
            launchContext: launchContext.diagnosticsValue
        )
    }

    private static var platformName: String {
        #if targetEnvironment(macCatalyst)
        return "Mac Catalyst"
        #elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return "iPadOS"
        }
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "Unknown"
        #endif
    }
}

@Model
public final class FeedbackDraft {
    @Attribute(.unique) public var id: UUID
    public var categoryRaw: String
    public var sourceRaw: String
    public var submissionStateRaw: String
    public var title: String
    public var summary: String
    public var stepsToReproduce: String
    public var expectedBehavior: String
    public var actualBehavior: String
    public var additionalContext: String
    public var roughNote: String
    public var diagnosticsJSON: String
    public var githubIssueURLString: String?
    public var failureMessage: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var submittedAt: Date?
    public var archivedAt: Date?
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        category: FeedbackCategory,
        source: FeedbackDraftSource,
        diagnostics: FeedbackDiagnostics,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.categoryRaw = category.rawValue
        self.sourceRaw = source.rawValue
        self.submissionStateRaw = FeedbackSubmissionState.draft.rawValue
        self.title = ""
        self.summary = ""
        self.stepsToReproduce = ""
        self.expectedBehavior = ""
        self.actualBehavior = ""
        self.additionalContext = ""
        self.roughNote = ""
        self.diagnosticsJSON = Self.encode(diagnostics)
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.archivedAt = nil
        self.deletedAt = nil
    }

    public var category: FeedbackCategory {
        get { FeedbackCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }

    public var source: FeedbackDraftSource {
        get { FeedbackDraftSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var submissionState: FeedbackSubmissionState {
        get { FeedbackSubmissionState(rawValue: submissionStateRaw) ?? .draft }
        set { submissionStateRaw = newValue.rawValue }
    }

    public var diagnostics: FeedbackDiagnostics {
        get {
            guard let data = diagnosticsJSON.data(using: .utf8),
                  let diagnostics = try? JSONDecoder().decode(FeedbackDiagnostics.self, from: data) else {
                return FeedbackDiagnostics(
                    appVersion: "Unknown",
                    buildNumber: "Unknown",
                    platform: "Unknown",
                    aiAvailability: "Unknown",
                    releaseControl: "Unknown"
                )
            }
            return diagnostics
        }
        set {
            diagnosticsJSON = Self.encode(newValue)
        }
    }

    public var githubIssueURL: URL? {
        get {
            guard let githubIssueURLString else { return nil }
            return URL(string: githubIssueURLString)
        }
        set {
            githubIssueURLString = newValue?.absoluteString
        }
    }

    public var hasMeaningfulContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !roughNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func encode(_ diagnostics: FeedbackDiagnostics) -> String {
        guard let data = try? JSONEncoder().encode(diagnostics),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

public enum FeedbackSchema {
    public static var all: [any PersistentModel.Type] {
        [FeedbackDraft.self]
    }
}
