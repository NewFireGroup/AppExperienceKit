import SwiftUI

public struct ReleaseControlLaunchReadiness: Sendable {
    public static let didPrepareNotification = Notification.Name("ReleaseControlLaunchReadiness.didPrepare")

    public init() {
    }

    @discardableResult
    public func prepare(
        using client: any ReleaseControlClient,
        settingsDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) async -> ReleaseControlStatus {
        await client.refresh()
        let status = await client.status()
        status.publishSettingsSnapshot(to: settingsDefaults)
        await MainActor.run {
            notificationCenter.post(name: Self.didPrepareNotification, object: nil)
        }
        return status
    }
}

public struct ReleaseControlLaunchGateView<Content: View>: View {
    @Environment(\.releaseControlClient) private var releaseControlClient
    @State private var isReady = false

    private let readiness: ReleaseControlLaunchReadiness
    private let hostConfiguration: AppExperienceHostConfiguration
    private let content: () -> Content

    public init(
        readiness: ReleaseControlLaunchReadiness = ReleaseControlLaunchReadiness(),
        hostConfiguration: AppExperienceHostConfiguration = .mainBundle(),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.readiness = readiness
        self.hostConfiguration = hostConfiguration
        self.content = content
    }

    public var body: some View {
        Group {
            if isReady {
                content()
            } else {
                ReleaseControlLaunchLoadingView(title: hostConfiguration.loadingTitle)
            }
        }
        .task {
            await prepareLaunchIfNeeded()
        }
    }

    @MainActor
    private func prepareLaunchIfNeeded() async {
        guard !isReady else { return }

        await readiness.prepare(using: releaseControlClient)
        isReady = true
    }
}

private struct ReleaseControlLaunchLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
