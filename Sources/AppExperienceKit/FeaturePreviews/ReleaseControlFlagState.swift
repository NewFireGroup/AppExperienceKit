import Foundation

public enum ReleaseControlFlagVariableSource: Sendable, Equatable {
    case optimizely
    case systemDefault

    public var displayName: String {
        switch self {
        case .optimizely:
            return "Optimizely"
        case .systemDefault:
            return "System default"
        }
    }
}

public struct ReleaseControlFlagVariableDetail: Identifiable, Sendable, Equatable {
    public let key: String
    public let value: String
    public let source: ReleaseControlFlagVariableSource

    public var id: String {
        key
    }
}

public struct ReleaseControlFlagState: Identifiable, Sendable, Equatable {
    private static let standardVariableDefaults: [(key: String, defaultValue: String)] = [
        ("flag_type", ReleaseControlFlagType.onDemand.rawValue),
        ("flag_control_type", ReleaseControlFlagControlType.optIn.rawValue)
    ]

    public let key: ReleaseControlKey
    public let displayName: String
    public let decision: ReleaseControlDecision
    public let providerStatus: ReleaseControlStatus
    public let preference: ReleaseControlPreference

    public init(
        key: ReleaseControlKey,
        decision: ReleaseControlDecision,
        providerStatus: ReleaseControlStatus,
        preference: ReleaseControlPreference = .systemDefault
    ) {
        self.key = key
        self.displayName = key.displayName
        self.decision = decision
        self.providerStatus = providerStatus
        self.preference = preference
    }

    public var id: ReleaseControlKey {
        key
    }

    public var stateLabel: String {
        if providerStatus.provider == .none || providerStatus.connectionState == .unavailable {
            return "Unavailable"
        }

        if decision.flagControlType == .optIn {
            switch preference {
            case .optOut:
                return "Off"
            case .optIn:
                return decision.isEnabled ? "Enabled" : "Requested"
            case .systemDefault:
                return decision.showsFeaturePreviewRow ? "Available" : "Disabled"
            }
        }

        if preference == .optOut {
            return "Off"
        }

        if decision.isEnabled {
            return "Enabled"
        }

        if preference == .optIn {
            return "Requested"
        }

        if decision.showsFeaturePreviewRow {
            return "Available"
        }

        return decision.isEnabled ? "Enabled" : "Disabled"
    }

    public var readOnlyToggleValue: Bool {
        preferenceToggleValue
    }

    public var preferenceToggleValue: Bool {
        if decision.flagControlType == .optIn {
            return preference == .optIn && decision.isEnabled
        }

        switch preference {
        case .systemDefault:
            return decision.isEnabled
        case .optIn:
            return true
        case .optOut:
            return false
        }
    }

    public var isVisibleInFeaturePreviews: Bool {
        return decision.showsFeaturePreviewRow || preference != .systemDefault
    }

    public var providerConnectionLabel: String {
        providerStatus.connectionDisplayName
    }

    public var variationLabel: String? {
        decision.variationKey
    }

    public var fallbackReason: String? {
        decision.reason ?? providerStatus.reason
    }

    public var variableDetails: [ReleaseControlFlagVariableDetail] {
        let standardKeys = Set(Self.standardVariableDefaults.map(\.key))
        let standardDetails = Self.standardVariableDefaults.map { variable in
            ReleaseControlFlagVariableDetail(
                key: variable.key,
                value: decision.variables[variable.key] ?? variable.defaultValue,
                source: decision.variables[variable.key] == nil ? .systemDefault : .optimizely
            )
        }
        let customDetails = decision.variables
            .filter { !standardKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map {
                ReleaseControlFlagVariableDetail(
                    key: $0.key,
                    value: $0.value,
                    source: .optimizely
                )
            }

        return standardDetails + customDetails
    }
}

public struct ReleaseControlFlagStateLoader: Sendable {
    private let keys: [ReleaseControlKey]
    private let preferenceStore: ReleaseControlPreferenceStore

    public init(
        keys: [ReleaseControlKey] = ReleaseControlKey.allCases,
        preferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore()
    ) {
        self.keys = keys
        self.preferenceStore = preferenceStore
    }

    public func load(using client: any ReleaseControlClient) async -> [ReleaseControlFlagState] {
        let status = await client.status()
        var states: [ReleaseControlFlagState] = []
        states.reserveCapacity(keys.count)

        for key in keys {
            let decision = await client.decision(for: key)
            let state = ReleaseControlFlagState(
                key: key,
                decision: decision,
                providerStatus: status,
                preference: preferenceStore.preference(for: key)
            )

            if state.isVisibleInFeaturePreviews {
                states.append(state)
            }
        }

        return states
    }

    public func refresh(using client: any ReleaseControlClient) async -> [ReleaseControlFlagState] {
        await client.refresh()
        return await load(using: client)
    }
}
