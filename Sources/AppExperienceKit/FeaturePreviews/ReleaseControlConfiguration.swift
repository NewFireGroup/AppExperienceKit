import Foundation

public enum ReleaseControlPreference: String, CaseIterable, Sendable, Equatable {
    case systemDefault = "default"
    case optIn = "opt_in"
    case optOut = "opt_out"

    public var displayName: String {
        switch self {
        case .systemDefault:
            return "Release setting"
        case .optIn:
            return "On"
        case .optOut:
            return "Off"
        }
    }
}

public final class ReleaseControlPreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let keyPrefix = "releaseControl.preference."
    public static let attributeKey = "release_control_preference"
    public static let preferenceDidChangeNotification = Notification.Name("ReleaseControlPreferenceStore.preferenceDidChange")
    public static let preferenceDidChangeReleaseControlKey = "releaseControlKey"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func preference(for key: ReleaseControlKey) -> ReleaseControlPreference {
        preference(for: key.descriptor)
    }

    public func preference(for descriptor: ReleaseControlDescriptor) -> ReleaseControlPreference {
        guard let rawValue = defaults.string(forKey: storageKey(for: descriptor)),
              let preference = ReleaseControlPreference(rawValue: rawValue)
        else {
            return .systemDefault
        }

        return preference
    }

    public func setPreference(
        _ preference: ReleaseControlPreference,
        for key: ReleaseControlKey,
        notifiesObservers: Bool = true
    ) {
        setPreference(preference, for: key.descriptor, notifiesObservers: notifiesObservers)
    }

    public func setPreference(
        _ preference: ReleaseControlPreference,
        for descriptor: ReleaseControlDescriptor,
        notifiesObservers: Bool = true
    ) {
        defaults.set(preference.rawValue, forKey: storageKey(for: descriptor))
        guard notifiesObservers else {
            return
        }

        postPreferenceDidChange(for: descriptor)
    }

    public func postPreferenceDidChange(for key: ReleaseControlKey) {
        postPreferenceDidChange(for: key.descriptor)
    }

    public func postPreferenceDidChange(for descriptor: ReleaseControlDescriptor) {
        NotificationCenter.default.post(
            name: Self.preferenceDidChangeNotification,
            object: self,
            userInfo: [Self.preferenceDidChangeReleaseControlKey: descriptor.key]
        )
    }

    public func attributes(for key: ReleaseControlKey) -> [String: String] {
        attributes(for: key.descriptor)
    }

    public func attributes(for descriptor: ReleaseControlDescriptor) -> [String: String] {
        [Self.attributeKey: preference(for: descriptor).rawValue]
    }

    private func storageKey(for key: ReleaseControlKey) -> String {
        storageKey(for: key.descriptor)
    }

    private func storageKey(for descriptor: ReleaseControlDescriptor) -> String {
        Self.keyPrefix + descriptor.key
    }
}

public struct ReleaseControlConfiguration: Sendable, Equatable {
    public let sdkKey: String?
    public let environmentKey: String?
    public let datafileURL: URL?
    public let userId: String
    public let attributes: [String: String]

    public init(sdkKey: String?) {
        self.init(
            sdkKey: sdkKey,
            environmentKey: nil,
            datafileURL: nil,
            userId: ReleaseControlInstallationID.current(),
            attributes: [:]
        )
    }

    public init(sdkKey: String?, userId: String) {
        self.init(sdkKey: sdkKey, environmentKey: nil, datafileURL: nil, userId: userId, attributes: [:])
    }

    public init(
        sdkKey: String?,
        environmentKey: String?,
        datafileURL: URL?,
        userId: String,
        attributes: [String: String] = [:]
    ) {
        self.sdkKey = ReleaseControlConfiguration.normalizedSDKKey(sdkKey)
        self.environmentKey = ReleaseControlConfiguration.normalizedConfigurationValue(environmentKey)
        self.datafileURL = datafileURL
        self.userId = userId
        self.attributes = attributes
    }

    public static func mainBundle(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        identityStore: AppIdentityStore = AppIdentityStore()
    ) -> ReleaseControlConfiguration {
        let resolvedExplicitSDKKey = firstNormalizedValue(
            defaults.string(forKey: "OptimizelySDKKey"),
            bundle.object(forInfoDictionaryKey: "OptimizelySDKKey") as? String
        )

        let environmentKey = firstNormalizedValue(
            defaults.string(forKey: "OptimizelyEnvironmentKey"),
            bundle.object(forInfoDictionaryKey: "OptimizelyEnvironmentKey") as? String,
            "development"
        )
        let developmentSDKKey = firstNormalizedValue(
            defaults.string(forKey: "OptimizelyDevelopmentSDKKey"),
            bundle.object(forInfoDictionaryKey: "OptimizelyDevelopmentSDKKey") as? String
        )
        let productionSDKKey = firstNormalizedValue(
            defaults.string(forKey: "OptimizelyProductionSDKKey"),
            bundle.object(forInfoDictionaryKey: "OptimizelyProductionSDKKey") as? String
        )
        let environmentSDKKey = sdkKey(
            for: environmentKey,
            developmentSDKKey: developmentSDKKey,
            productionSDKKey: productionSDKKey
        )
        let userID = firstNormalizedValue(
            defaults.string(forKey: "OptimizelyUserID"),
            bundle.object(forInfoDictionaryKey: "OptimizelyUserID") as? String
        )
        let resolvedUserID = userID ?? ReleaseControlInstallationID.current(defaults: defaults)

        return ReleaseControlConfiguration(
            sdkKey: resolvedExplicitSDKKey ?? environmentSDKKey,
            environmentKey: environmentKey,
            datafileURL: datafileURL(for: resolvedExplicitSDKKey ?? environmentSDKKey),
            userId: resolvedUserID,
            attributes: attributes(
                userId: resolvedUserID,
                environmentKey: environmentKey,
                isExplicitUserOverride: userID != nil,
                identityStore: identityStore
            )
        )
    }

    public static func normalizedSDKKey(_ value: String?) -> String? {
        normalizedConfigurationValue(value)
    }

    public func decisionAttributes(
        for key: ReleaseControlKey,
        preferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore()
    ) -> [String: String] {
        decisionAttributes(for: key.descriptor, preferenceStore: preferenceStore)
    }

    public func decisionAttributes(
        for descriptor: ReleaseControlDescriptor,
        preferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore()
    ) -> [String: String] {
        var values = attributes
        values.merge(
            preferenceStore.attributes(for: descriptor),
            uniquingKeysWith: { _, preferenceValue in preferenceValue }
        )
        return values
    }

    public func decisionDiagnostics(
        for key: ReleaseControlKey,
        variationKey: String?,
        attributes currentAttributes: [String: String]? = nil
    ) -> [String: String] {
        decisionDiagnostics(for: key.descriptor, variationKey: variationKey, attributes: currentAttributes)
    }

    public func decisionDiagnostics(
        for descriptor: ReleaseControlDescriptor,
        variationKey: String?,
        attributes currentAttributes: [String: String]? = nil
    ) -> [String: String] {
        var values = currentAttributes ?? attributes
        values["release_control_flag_key"] = descriptor.key

        if let variationKey {
            values["release_control_variation_key"] = variationKey
        }

        return values
    }

    private static func normalizedConfigurationValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.contains("$(")
        else {
            return nil
        }

        return trimmed
    }

    private static func firstNormalizedValue(_ values: String?...) -> String? {
        values.lazy.compactMap(normalizedConfigurationValue).first
    }

    private static func sdkKey(
        for environmentKey: String?,
        developmentSDKKey: String?,
        productionSDKKey: String?
    ) -> String? {
        switch environmentKey {
        case "production":
            return productionSDKKey
        case "development":
            return developmentSDKKey
        default:
            return nil
        }
    }

    private static func datafileURL(for sdkKey: String?) -> URL? {
        guard let sdkKey else {
            return nil
        }

        return URL(string: "https://cdn.optimizely.com/datafiles/\(sdkKey).json")
    }

    private static func attributes(
        userId: String,
        environmentKey: String?,
        isExplicitUserOverride: Bool,
        identityStore: AppIdentityStore
    ) -> [String: String] {
        var values = [
            "release_control_user_id": userId,
            "release_control_identity_source": isExplicitUserOverride ? "explicit_override" : "anonymous_installation",
            "auth_state": isExplicitUserOverride ? "test_override" : identityStore.authState.rawValue
        ]

        if let environmentKey {
            values["release_control_environment"] = environmentKey
        }

        return values
    }
}

private enum ReleaseControlInstallationID {
    private static let key = "releaseControl.installationId"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key) {
            return existing
        }

        let created = UUID().uuidString
        defaults.set(created, forKey: key)
        return created
    }
}
