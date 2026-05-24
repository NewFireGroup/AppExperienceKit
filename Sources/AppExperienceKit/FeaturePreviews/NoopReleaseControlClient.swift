import Foundation

public struct NoopReleaseControlClient: ReleaseControlClient {
    private let reason: String

    public init(reason: String = "Release controls are not configured") {
        self.reason = reason
    }

    public func status() async -> ReleaseControlStatus {
        .none(reason: reason)
    }

    public func decision(for key: ReleaseControlKey) async -> ReleaseControlDecision {
        .disabled(key, reason: reason)
    }

    public func decision(for descriptor: ReleaseControlDescriptor) async -> ReleaseControlDescriptorDecision {
        .disabled(descriptor, reason: reason)
    }

    public func track(_ event: ReleaseControlEvent) async {
    }

    public func track(_ event: ReleaseControlCustomEvent) async {
    }
}
