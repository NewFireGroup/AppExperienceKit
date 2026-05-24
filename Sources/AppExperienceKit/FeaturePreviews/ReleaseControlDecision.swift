import Foundation

enum ReleaseControlBoolVariable {
    static func normalizedString(stringValue: String?, boolValue: Bool?) -> String? {
        if let boolValue {
            return boolValue ? "true" : "false"
        }

        return stringValue
    }

    static func isEnabled(_ rawValue: String?) -> Bool {
        guard let rawValue else {
            return false
        }

        return ["true", "1", "yes", "enabled", "on"].contains(rawValue.lowercased())
    }
}

public enum AuthenticationAppLockMode: String, Sendable, Equatable {
    case launchOnly = "launch_only"
}

public enum ReleaseControlFlagType: String, Sendable, Equatable {
    case appLaunch = "app_launch"
    case extensionLaunch = "extension_launch"
    case onDemand = "on_demand"
}

public enum ReleaseControlFlagControlType: String, Sendable, Equatable {
    case optIn = "opt_in"
    case optOut = "opt_out"
}

public struct ReleaseControlDecision: Sendable, Equatable {
    public let key: ReleaseControlKey
    public let isEnabled: Bool
    public let variationKey: String?
    public let variables: [String: String]
    public let diagnostics: [String: String]
    public let reason: String?

    public init(
        key: ReleaseControlKey,
        isEnabled: Bool,
        variationKey: String? = nil,
        variables: [String: String] = [:],
        diagnostics: [String: String] = [:],
        reason: String? = nil
    ) {
        self.key = key
        self.isEnabled = isEnabled
        self.variationKey = variationKey
        self.variables = variables
        self.diagnostics = diagnostics
        self.reason = reason
    }

    public static func disabled(_ key: ReleaseControlKey, reason: String? = nil) -> ReleaseControlDecision {
        ReleaseControlDecision(key: key, isEnabled: false, reason: reason)
    }

    public func applying(_ preference: ReleaseControlPreference) -> ReleaseControlDecision {
        guard isEnabled else {
            return self
        }

        switch flagControlType {
        case .optIn where preference != .optIn:
            return ReleaseControlDecision(
                key: key,
                isEnabled: false,
                variationKey: variationKey,
                variables: variables,
                diagnostics: diagnostics,
                reason: preference == .optOut ? "Local preference is off" : "Local opt-in is required"
            )
        case .optOut where preference == .optOut:
            return ReleaseControlDecision(
                key: key,
                isEnabled: false,
                variationKey: variationKey,
                variables: variables,
                diagnostics: diagnostics,
                reason: "Local preference is off"
            )
        default:
            return self
        }
    }

    public var flagType: ReleaseControlFlagType {
        guard let rawValue = stringValue(for: "flag_type"),
              let flagType = ReleaseControlFlagType(rawValue: rawValue)
        else {
            return .onDemand
        }

        return flagType
    }

    public var flagControlType: ReleaseControlFlagControlType {
        guard let rawValue = stringValue(for: "flag_control_type"),
              let controlType = ReleaseControlFlagControlType(rawValue: rawValue)
        else {
            return .optIn
        }

        return controlType
    }

    public func isActive(preference: ReleaseControlPreference) -> Bool {
        applying(preference).isEnabled
    }

    public func isAppLaunchActive(preference: ReleaseControlPreference) -> Bool {
        flagType == .appLaunch && isActive(preference: preference)
    }

    public func isExtensionLaunchActive(preference: ReleaseControlPreference) -> Bool {
        flagType == .extensionLaunch && isActive(preference: preference)
    }

    public var showsPlanningNavigation: Bool {
        key == .planning && isEnabled
    }

    public var showsPlanningEditor: Bool {
        key == .planningEditor && isEnabled
    }

    public var showsFeedbackSettings: Bool {
        key == .feedbackFeature && isEnabled
    }

    public var showsFeedbackNavigation: Bool {
        key == .feedbackFeature && isEnabled
    }

    public var showsCashflowCalendarYearScheduling: Bool {
        key == .cashflowCalendarYearFeature && isEnabled
    }

    public var showsAuthenticationPreview: Bool {
        guard key == .authenticationFeature else {
            return false
        }

        return isEnabled
    }

    public func isAuthenticationActive(preference: ReleaseControlPreference) -> Bool {
        key == .authenticationFeature && isActive(preference: preference)
    }

    public func isAuthenticationAppLockAvailable(preference: ReleaseControlPreference) -> Bool {
        isAuthenticationActive(preference: preference) && boolValue(for: "app_lock_available") == true
    }

    public func isAuthenticationGitHubLinkingAvailable(preference: ReleaseControlPreference) -> Bool {
        isAuthenticationActive(preference: preference) && boolValue(for: "github_linking_available") == true
    }

    public var authenticationAppLockMode: AuthenticationAppLockMode {
        guard let rawValue = stringValue(for: "app_lock_mode"),
              let mode = AuthenticationAppLockMode(rawValue: rawValue)
        else {
            return .launchOnly
        }

        return mode
    }

    public var showsFeaturePreviewRow: Bool {
        isEnabled
    }

    public var allowsFeedbackAIAssist: Bool {
        guard key == .feedbackFeature, isEnabled else {
            return false
        }

        let value = variables["ai_assist_enabled"] ?? variables["ai_enabled"]
        guard let value else {
            return false
        }

        return ReleaseControlBoolVariable.isEnabled(value)
    }

    public func stringValue(for variableKey: String) -> String? {
        variables[variableKey]
    }

    public func boolValue(for variableKey: String) -> Bool? {
        guard let value = variables[variableKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty
        else {
            return nil
        }

        if ["true", "1", "yes", "enabled", "on"].contains(value) {
            return true
        }

        if ["false", "0", "no", "disabled", "off"].contains(value) {
            return false
        }

        return nil
    }

    public func diagnosticValue(for diagnosticKey: String) -> String? {
        diagnostics[diagnosticKey]
    }
}

public struct ReleaseControlDescriptorDecision: Sendable, Equatable {
    public let descriptor: ReleaseControlDescriptor
    public let isEnabled: Bool
    public let variationKey: String?
    public let variables: [String: String]
    public let diagnostics: [String: String]
    public let reason: String?

    public init(
        descriptor: ReleaseControlDescriptor,
        isEnabled: Bool,
        variationKey: String? = nil,
        variables: [String: String] = [:],
        diagnostics: [String: String] = [:],
        reason: String? = nil
    ) {
        self.descriptor = descriptor
        self.isEnabled = isEnabled
        self.variationKey = variationKey
        self.variables = variables
        self.diagnostics = diagnostics
        self.reason = reason
    }

    public init(decision: ReleaseControlDecision, descriptor: ReleaseControlDescriptor? = nil) {
        self.init(
            descriptor: descriptor ?? decision.key.descriptor,
            isEnabled: decision.isEnabled,
            variationKey: decision.variationKey,
            variables: decision.variables,
            diagnostics: decision.diagnostics,
            reason: decision.reason
        )
    }

    public static func disabled(
        _ descriptor: ReleaseControlDescriptor,
        reason: String? = nil
    ) -> ReleaseControlDescriptorDecision {
        ReleaseControlDescriptorDecision(descriptor: descriptor, isEnabled: false, reason: reason)
    }

    public func applying(_ preference: ReleaseControlPreference) -> ReleaseControlDescriptorDecision {
        guard isEnabled else {
            return self
        }

        switch flagControlType {
        case .optIn where preference != .optIn:
            return ReleaseControlDescriptorDecision(
                descriptor: descriptor,
                isEnabled: false,
                variationKey: variationKey,
                variables: variables,
                diagnostics: diagnostics,
                reason: preference == .optOut ? "Local preference is off" : "Local opt-in is required"
            )
        case .optOut where preference == .optOut:
            return ReleaseControlDescriptorDecision(
                descriptor: descriptor,
                isEnabled: false,
                variationKey: variationKey,
                variables: variables,
                diagnostics: diagnostics,
                reason: "Local preference is off"
            )
        default:
            return self
        }
    }

    public var flagType: ReleaseControlFlagType {
        guard let rawValue = stringValue(for: "flag_type"),
              let flagType = ReleaseControlFlagType(rawValue: rawValue)
        else {
            return .onDemand
        }

        return flagType
    }

    public var flagControlType: ReleaseControlFlagControlType {
        guard let rawValue = stringValue(for: "flag_control_type"),
              let controlType = ReleaseControlFlagControlType(rawValue: rawValue)
        else {
            return .optIn
        }

        return controlType
    }

    public func isActive(preference: ReleaseControlPreference) -> Bool {
        applying(preference).isEnabled
    }

    public var showsFeaturePreviewRow: Bool {
        isEnabled
    }

    public func stringValue(for variableKey: String) -> String? {
        variables[variableKey]
    }

    public func boolValue(for variableKey: String) -> Bool? {
        guard let value = variables[variableKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty
        else {
            return nil
        }

        if ["true", "1", "yes", "enabled", "on"].contains(value) {
            return true
        }

        if ["false", "0", "no", "disabled", "off"].contains(value) {
            return false
        }

        return nil
    }

    public func diagnosticValue(for diagnosticKey: String) -> String? {
        diagnostics[diagnosticKey]
    }
}
