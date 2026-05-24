import SwiftUI

private struct ReleaseControlClientKey: EnvironmentKey {
    static let defaultValue: any ReleaseControlClient = NoopReleaseControlClient()
}

public extension EnvironmentValues {
    var releaseControlClient: any ReleaseControlClient {
        get { self[ReleaseControlClientKey.self] }
        set { self[ReleaseControlClientKey.self] = newValue }
    }
}

public extension View {
    func releaseControlClient(_ client: any ReleaseControlClient) -> some View {
        environment(\.releaseControlClient, client)
    }
}
