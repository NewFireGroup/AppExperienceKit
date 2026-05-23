import Foundation

public enum ReleaseControlProvider: String, Sendable, Equatable {
    case none
    case optimizely

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .optimizely:
            return "Optimizely"
        }
    }
}

public enum ReleaseControlConnectionState: String, Sendable, Equatable {
    case unavailable
    case connecting
    case connected
    case offline

    public var displayName: String {
        switch self {
        case .unavailable:
            return "Unavailable"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .offline:
            return "Offline"
        }
    }
}

public struct ReleaseControlStatus: Sendable, Equatable {
    public let provider: ReleaseControlProvider
    public let connectionState: ReleaseControlConnectionState
    public let environmentKey: String?
    public let userId: String?
    public let datafileURL: URL?
    public let reason: String?

    public init(
        provider: ReleaseControlProvider,
        connectionState: ReleaseControlConnectionState,
        environmentKey: String? = nil,
        userId: String? = nil,
        datafileURL: URL? = nil,
        reason: String? = nil
    ) {
        self.provider = provider
        self.connectionState = connectionState
        self.environmentKey = environmentKey
        self.userId = userId
        self.datafileURL = datafileURL
        self.reason = reason
    }

    public static func none(reason: String? = nil) -> ReleaseControlStatus {
        ReleaseControlStatus(
            provider: .none,
            connectionState: .unavailable,
            reason: reason
        )
    }

    public static func optimizely(
        configuration: ReleaseControlConfiguration,
        connectionState: ReleaseControlConnectionState,
        reason: String? = nil
    ) -> ReleaseControlStatus {
        ReleaseControlStatus(
            provider: .optimizely,
            connectionState: connectionState,
            environmentKey: configuration.environmentKey,
            userId: configuration.userId,
            datafileURL: configuration.datafileURL,
            reason: reason
        )
    }

    public var shouldShowInSettings: Bool {
        provider != .none
    }

    public var providerDisplayName: String {
        provider.displayName
    }

    public var connectionDisplayName: String {
        connectionState.displayName
    }

    public var environmentDisplayName: String {
        environmentKey ?? "Unknown"
    }

    public var userDisplayName: String {
        userId ?? "Not configured"
    }

    public var datafileDisplayName: String {
        datafileURL == nil ? "Not configured" : "Configured"
    }

    public func publishSettingsSnapshot(to defaults: UserDefaults = .standard) {
        defaults.set(providerDisplayName, forKey: ReleaseControlSettingsKey.provider)
        defaults.set(connectionDisplayName, forKey: ReleaseControlSettingsKey.connectionState)
        defaults.set(environmentKey ?? "Not configured", forKey: ReleaseControlSettingsKey.environment)
        defaults.set(userDisplayName, forKey: ReleaseControlSettingsKey.userId)
        defaults.set(datafileDisplayName, forKey: ReleaseControlSettingsKey.datafileURL)
    }
}

public enum ReleaseControlSettingsKey {
    public static let provider = "releaseControl.settings.provider"
    public static let connectionState = "releaseControl.settings.connectionState"
    public static let environment = "releaseControl.settings.environment"
    public static let userId = "releaseControl.settings.userId"
    public static let datafileURL = "releaseControl.settings.datafileURL"
}

public extension ReleaseControlClient {
    func publishSettingsSnapshot(to defaults: UserDefaults = .standard) async {
        let status = await status()
        status.publishSettingsSnapshot(to: defaults)
    }
}
