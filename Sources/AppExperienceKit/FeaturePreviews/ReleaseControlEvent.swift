import Foundation

public struct ReleaseControlCustomEvent: Sendable, Equatable {
    public let releaseControl: ReleaseControlDescriptor
    public let key: String
    public let eventProperties: [String: String]

    public init(
        releaseControl: ReleaseControlDescriptor,
        key: String,
        eventProperties: [String: String] = [:]
    ) {
        self.releaseControl = releaseControl
        self.key = key
        self.eventProperties = eventProperties
    }

    public var eventTags: [String: Any] {
        guard !eventProperties.isEmpty else { return [:] }
        return ["$opt_event_properties": eventProperties]
    }
}

public enum ReleaseControlEvent: Sendable, Equatable {
    case planningFeatureOpened(variationKey: String?)
    case planningEditorOpened(variationKey: String?)
    case feedbackFeatureOpened(launchSource: String, variationKey: String?)
    case feedbackFormStarted(category: String, source: String, launchSource: String, variationKey: String?)
    case feedbackAIAssistOpened(category: String, source: String, launchSource: String, variationKey: String?)
    case feedbackAIAssistUsed(category: String, source: String, aiResult: String, launchSource: String, variationKey: String?)
    case feedbackAIAssistCanceled(category: String, source: String, launchSource: String, variationKey: String?)
    case feedbackSubmitted(category: String, source: String, destination: String, launchSource: String, variationKey: String?)
    case feedbackFormAbandoned(category: String, source: String, launchSource: String, variationKey: String?)
    case authenticationFeatureOptedIn(launchSource: String, previousPreference: String, variationKey: String?)
    case authenticationFeatureOptedOut(launchSource: String, previousPreference: String, variationKey: String?)
    case authenticationAppLockEnabled(launchSource: String, lockMode: String, variationKey: String?)
    case authenticationAppLockDisabled(launchSource: String, lockMode: String, variationKey: String?)
    case authenticationAppUnlockCompleted(result: String, lockMode: String, variationKey: String?)
    case authenticationAppUnlockFailed(result: String, lockMode: String, variationKey: String?)
    case authenticationGitHubLinkStarted(launchSource: String, variationKey: String?)
    case authenticationGitHubLinked(launchSource: String, variationKey: String?)
    case authenticationGitHubUnlinked(launchSource: String, variationKey: String?)
    case authenticationGitHubCredentialUsed(launchSource: String, destination: String, variationKey: String?)
    case cashflowCalendarYearFeatureOpened(variationKey: String?)
    case cashflowCalendarYearScheduleSaved(variationKey: String?)

    public var key: String {
        switch self {
        case .planningFeatureOpened:
            return "planning_feature_opened"
        case .planningEditorOpened:
            return "planning_editor_opened"
        case .feedbackFeatureOpened:
            return "feedback_feature_opened"
        case .feedbackFormStarted:
            return "feedback_form_started"
        case .feedbackAIAssistOpened:
            return "feedback_ai_assist_opened"
        case .feedbackAIAssistUsed:
            return "feedback_ai_assist_used"
        case .feedbackAIAssistCanceled:
            return "feedback_ai_assist_canceled"
        case .feedbackSubmitted:
            return "feedback_submitted"
        case .feedbackFormAbandoned:
            return "feedback_form_abandoned"
        case .authenticationFeatureOptedIn:
            return "authentication_feature_opted_in"
        case .authenticationFeatureOptedOut:
            return "authentication_feature_opted_out"
        case .authenticationAppLockEnabled:
            return "authentication_app_lock_enabled"
        case .authenticationAppLockDisabled:
            return "authentication_app_lock_disabled"
        case .authenticationAppUnlockCompleted:
            return "authentication_app_unlock_completed"
        case .authenticationAppUnlockFailed:
            return "authentication_app_unlock_failed"
        case .authenticationGitHubLinkStarted:
            return "authentication_github_link_started"
        case .authenticationGitHubLinked:
            return "authentication_github_linked"
        case .authenticationGitHubUnlinked:
            return "authentication_github_unlinked"
        case .authenticationGitHubCredentialUsed:
            return "authentication_github_credential_used"
        case .cashflowCalendarYearFeatureOpened:
            return "cashflow_calendar_year_feature_opened"
        case .cashflowCalendarYearScheduleSaved:
            return "cashflow_calendar_year_schedule_saved"
        }
    }

    public var releaseControlKey: ReleaseControlKey {
        switch self {
        case .planningFeatureOpened:
            return .planning
        case .planningEditorOpened:
            return .planningEditor
        case .feedbackFeatureOpened,
             .feedbackFormStarted,
             .feedbackAIAssistOpened,
             .feedbackAIAssistUsed,
             .feedbackAIAssistCanceled,
             .feedbackSubmitted,
             .feedbackFormAbandoned:
            return .feedbackFeature
        case .authenticationFeatureOptedIn,
             .authenticationFeatureOptedOut,
             .authenticationAppLockEnabled,
             .authenticationAppLockDisabled,
             .authenticationAppUnlockCompleted,
             .authenticationAppUnlockFailed,
             .authenticationGitHubLinkStarted,
             .authenticationGitHubLinked,
             .authenticationGitHubUnlinked,
             .authenticationGitHubCredentialUsed:
            return .authenticationFeature
        case .cashflowCalendarYearFeatureOpened,
             .cashflowCalendarYearScheduleSaved:
            return .cashflowCalendarYearFeature
        }
    }

    public var eventProperties: [String: String] {
        switch self {
        case .planningFeatureOpened(let variationKey),
             .planningEditorOpened(let variationKey),
             .cashflowCalendarYearFeatureOpened(let variationKey),
             .cashflowCalendarYearScheduleSaved(let variationKey):
            return Self.properties(variationKey: variationKey)
        case let .feedbackFeatureOpened(launchSource, variationKey):
            return Self.properties(launchSource: launchSource, variationKey: variationKey)
        case let .feedbackFormStarted(category, source, launchSource, variationKey),
             let .feedbackAIAssistOpened(category, source, launchSource, variationKey),
             let .feedbackAIAssistCanceled(category, source, launchSource, variationKey),
             let .feedbackFormAbandoned(category, source, launchSource, variationKey):
            var properties = [
                "category": category,
                "launch_source": launchSource,
                "source": source
            ]
            if let variationKey {
                properties["variation_key"] = variationKey
            }
            return properties
        case let .feedbackAIAssistUsed(category, source, aiResult, launchSource, variationKey):
            var tags = [
                "ai_result": aiResult,
                "category": category,
                "launch_source": launchSource,
                "source": source
            ]
            if let variationKey {
                tags["variation_key"] = variationKey
            }
            return tags
        case let .feedbackSubmitted(category, source, destination, launchSource, variationKey):
            var properties = [
                "category": category,
                "destination": destination,
                "launch_source": launchSource,
                "source": source
            ]
            if let variationKey {
                properties["variation_key"] = variationKey
            }
            return properties
        case let .authenticationFeatureOptedIn(launchSource, previousPreference, variationKey),
             let .authenticationFeatureOptedOut(launchSource, previousPreference, variationKey):
            var properties = [
                "launch_source": launchSource,
                "previous_preference": previousPreference
            ]
            if let variationKey {
                properties["variation_key"] = variationKey
            }
            return properties
        case let .authenticationAppLockEnabled(launchSource, lockMode, variationKey),
             let .authenticationAppLockDisabled(launchSource, lockMode, variationKey):
            var properties = [
                "launch_source": launchSource,
                "lock_mode": lockMode
            ]
            if let variationKey {
                properties["variation_key"] = variationKey
            }
            return properties
        case let .authenticationAppUnlockCompleted(result, lockMode, variationKey),
             let .authenticationAppUnlockFailed(result, lockMode, variationKey):
            var properties = [
                "lock_mode": lockMode,
                "result": result
            ]
            if let variationKey {
                properties["variation_key"] = variationKey
            }
            return properties
        case let .authenticationGitHubLinkStarted(launchSource, variationKey),
             let .authenticationGitHubLinked(launchSource, variationKey),
             let .authenticationGitHubUnlinked(launchSource, variationKey):
            return Self.properties(launchSource: launchSource, variationKey: variationKey)
        case let .authenticationGitHubCredentialUsed(launchSource, destination, variationKey):
            var properties = [
                "destination": destination,
                "launch_source": launchSource
            ]
            if let variationKey {
                properties["variation_key"] = variationKey
            }
            return properties
        }
    }

    public var eventTags: [String: Any] {
        let properties = eventProperties
        guard !properties.isEmpty else { return [:] }
        return ["$opt_event_properties": properties]
    }

    private static func properties(variationKey: String?) -> [String: String] {
        guard let variationKey else { return [:] }
        return ["variation_key": variationKey]
    }

    private static func properties(launchSource: String, variationKey: String?) -> [String: String] {
        var properties = ["launch_source": launchSource]
        if let variationKey {
            properties["variation_key"] = variationKey
        }
        return properties
    }
}
