import Foundation

public protocol ReleaseControlClient: Sendable {
    func status() async -> ReleaseControlStatus
    func refresh() async
    func decision(for key: ReleaseControlKey) async -> ReleaseControlDecision
    func track(_ event: ReleaseControlEvent) async
}

public extension ReleaseControlClient {
    func refresh() async {
    }

    func activeDecision(
        for key: ReleaseControlKey,
        preferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore()
    ) async -> ReleaseControlDecision {
        let decision = await decision(for: key)
        return decision.applying(preferenceStore.preference(for: key))
    }
}
