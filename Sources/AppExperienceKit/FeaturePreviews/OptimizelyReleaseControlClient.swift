import Foundation
import Optimizely
import OSLog

public final class OptimizelyReleaseControlClient: ReleaseControlClient, @unchecked Sendable {
    private let client: OptimizelyClient
    private let configuration: ReleaseControlConfiguration
    private let preferenceStore: ReleaseControlPreferenceStore
    private let identityStore: AppIdentityStore
    private let runtimeStatus = OptimizelyRuntimeStatus()
    private let userId: String
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AppExperienceKit",
        category: "OptimizelyReleaseControl"
    )

    public init?(
        configuration: ReleaseControlConfiguration = .mainBundle(),
        preferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore(),
        identityStore: AppIdentityStore = AppIdentityStore()
    ) {
        guard let sdkKey = configuration.sdkKey else {
            return nil
        }

        self.client = OptimizelyClient(sdkKey: sdkKey)
        self.configuration = configuration
        self.preferenceStore = preferenceStore
        self.identityStore = identityStore
        self.userId = configuration.userId
    }

    public func status() async -> ReleaseControlStatus {
        await runtimeStatus.status(configuration: configuration)
    }

    public func refresh() async {
        do {
            try await client.start(resourceTimeout: 5)
            await runtimeStatus.markConnected()
        } catch {
            await runtimeStatus.markOffline(reason: String(describing: error))
            logger.error("Failed to refresh Optimizely SDK: \(String(describing: error), privacy: .public)")
        }
    }

    public func decision(for key: ReleaseControlKey) async -> ReleaseControlDecision {
        let attributes = currentAttributes(for: key)
        let user = client.createUserContext(userId: userId, attributes: attributes)
        let decision = user.decide(key: key.rawValue)
        let placeholderTitle: String? = decision.variables.getValue(jsonPath: "placeholder_title")
        let placeholderBody: String? = decision.variables.getValue(jsonPath: "placeholder_body")
        let aiAssistEnabled = Self.booleanVariableString(
            from: decision.variables,
            key: "ai_assist_enabled"
        )
        let aiEnabled = Self.booleanVariableString(
            from: decision.variables,
            key: "ai_enabled"
        )
        let appLockAvailable = Self.booleanVariableString(
            from: decision.variables,
            key: "app_lock_available"
        )
        let githubLinkingAvailable = Self.booleanVariableString(
            from: decision.variables,
            key: "github_linking_available"
        )
        let flagType: String? = decision.variables.getValue(jsonPath: "flag_type")
        let flagControlType: String? = decision.variables.getValue(jsonPath: "flag_control_type")
        let appLockMode: String? = decision.variables.getValue(jsonPath: "app_lock_mode")
        let variables = [
            "placeholder_title": placeholderTitle,
            "placeholder_body": placeholderBody,
            "ai_assist_enabled": aiAssistEnabled,
            "ai_enabled": aiEnabled,
            "app_lock_available": appLockAvailable,
            "github_linking_available": githubLinkingAvailable,
            "flag_type": flagType,
            "flag_control_type": flagControlType,
            "app_lock_mode": appLockMode
        ].compactMapValues { $0 }

        return ReleaseControlDecision(
            key: key,
            isEnabled: decision.enabled,
            variationKey: decision.variationKey,
            variables: variables,
            diagnostics: configuration.decisionDiagnostics(
                for: key,
                variationKey: decision.variationKey,
                attributes: attributes
            ),
            reason: decision.reasons.first
        )
    }

    public func track(_ event: ReleaseControlEvent) async {
        let attributes = currentAttributes(for: event.releaseControlKey)
        let user = client.createUserContext(userId: userId, attributes: attributes)

        do {
            try user.trackEvent(eventKey: event.key, eventTags: event.eventTags)
        } catch {
            logger.error("Failed to track Optimizely event \(event.key, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private static func booleanVariableString(from variables: OptimizelyJSON, key: String) -> String? {
        let boolValue: Bool? = variables.getValue(jsonPath: key)
        if let boolValue {
            return ReleaseControlBoolVariable.normalizedString(stringValue: nil, boolValue: boolValue)
        }

        let stringValue: String? = variables.getValue(jsonPath: key)
        return ReleaseControlBoolVariable.normalizedString(stringValue: stringValue, boolValue: nil)
    }

    private func currentAttributes(for key: ReleaseControlKey) -> [String: String] {
        var attributes = configuration.decisionAttributes(for: key, preferenceStore: preferenceStore)
        if attributes["release_control_identity_source"] != "explicit_override" {
            attributes["auth_state"] = identityStore.authState.rawValue
        }
        return attributes
    }
}

private actor OptimizelyRuntimeStatus {
    private var connectionState: ReleaseControlConnectionState = .connecting
    private var reason: String?

    func markConnected() {
        connectionState = .connected
        reason = nil
    }

    func markOffline(reason: String) {
        connectionState = .offline
        self.reason = reason
    }

    func status(configuration: ReleaseControlConfiguration) -> ReleaseControlStatus {
        .optimizely(
            configuration: configuration,
            connectionState: connectionState,
            reason: reason
        )
    }
}
