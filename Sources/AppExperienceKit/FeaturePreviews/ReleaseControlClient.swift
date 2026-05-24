import Foundation

public protocol ReleaseControlDescriptorClient: Sendable {
    func status() async -> ReleaseControlStatus
    func refresh() async
    func decision(for descriptor: ReleaseControlDescriptor) async -> ReleaseControlDescriptorDecision
    func track(_ event: ReleaseControlCustomEvent) async
}

public protocol ReleaseControlClient: ReleaseControlDescriptorClient {
    func decision(for key: ReleaseControlKey) async -> ReleaseControlDecision
    func track(_ event: ReleaseControlEvent) async
}

public extension ReleaseControlDescriptorClient {
    func refresh() async {
    }

    func track(_ event: ReleaseControlCustomEvent) async {
    }
}

public extension ReleaseControlClient {
    func decision(for descriptor: ReleaseControlDescriptor) async -> ReleaseControlDescriptorDecision {
        guard let key = ReleaseControlKey(rawValue: descriptor.key) else {
            return .disabled(descriptor, reason: "Release control is not supported by this client")
        }

        return ReleaseControlDescriptorDecision(
            decision: await decision(for: key),
            descriptor: descriptor
        )
    }

    func activeDecision(
        for key: ReleaseControlKey,
        preferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore()
    ) async -> ReleaseControlDecision {
        let decision = await decision(for: key)
        return decision.applying(preferenceStore.preference(for: key))
    }
}
