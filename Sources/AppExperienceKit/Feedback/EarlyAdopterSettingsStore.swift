import Foundation

public enum GitHubConnectionState: Equatable, Sendable {
    case connected
    case disconnected
}

public protocol GitHubTokenStore: AnyObject {
    func loadToken() -> String?
    func saveToken(_ token: String)
    func deleteToken()
}

public final class EarlyAdopterSettingsStore {
    public static let provideFeedbackKey = "earlyAdopters.provideFeedback"
    public static let appleAssistKey = "earlyAdopters.appleAssist"
    public static let startPhoneFeedbackWithAppleAssistKey = "earlyAdopters.startPhoneFeedbackWithAppleAssist"
    public static let startFeedbackWithAppleAssistKey = startPhoneFeedbackWithAppleAssistKey

    private let defaults: UserDefaults
    private let tokenStore: GitHubTokenStore

    public init(
        defaults: UserDefaults = .standard,
        tokenStore: GitHubTokenStore = KeychainGitHubTokenStore()
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore
    }

    public var isFeedbackEnabled: Bool {
        defaults.bool(forKey: Self.provideFeedbackKey)
    }

    public var isAppleAssistEnabled: Bool {
        defaults.bool(forKey: Self.appleAssistKey)
    }

    public var startsPhoneFeedbackWithAppleAssist: Bool {
        startsFeedbackWithAppleAssist
    }

    public var startsFeedbackWithAppleAssist: Bool {
        defaults.bool(forKey: Self.startPhoneFeedbackWithAppleAssistKey)
    }

    public var githubConnectionState: GitHubConnectionState {
        tokenStore.loadToken() == nil ? .disconnected : .connected
    }

    public func setFeedbackEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.provideFeedbackKey)
    }

    public func setAppleAssistEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.appleAssistKey)
    }

    public func setStartsPhoneFeedbackWithAppleAssist(_ enabled: Bool) {
        setStartsFeedbackWithAppleAssist(enabled)
    }

    public func setStartsFeedbackWithAppleAssist(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.startPhoneFeedbackWithAppleAssistKey)
    }

    public func disableAppleAssistIfUnavailable(_ availability: FeedbackAIAvailability) {
        guard !FeedbackAIAssistSettings.canEnable(availability: availability) else { return }

        setAppleAssistEnabled(false)
        setStartsFeedbackWithAppleAssist(false)
    }

    public func disconnectGitHub() {
        tokenStore.deleteToken()
    }
}
