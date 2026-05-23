import SwiftUI

public struct ReleaseControlFlagStatesView: View {
    @Environment(\.releaseControlClient) private var releaseControlClient

    @State private var states: [ReleaseControlFlagState] = []
    @State private var providerStatus: ReleaseControlStatus?
    @State private var isLoading = true
    @State private var isRefreshing = false

    private let loader: ReleaseControlFlagStateLoader
    private let preferenceStore: ReleaseControlPreferenceStore

    public init(
        preferenceStore: ReleaseControlPreferenceStore = ReleaseControlPreferenceStore()
    ) {
        self.preferenceStore = preferenceStore
        self.loader = ReleaseControlFlagStateLoader(preferenceStore: preferenceStore)
    }

    public var body: some View {
        List {
            Section {
                Text("Feature Previews lists available app features for this device. Switches save this device's preference and refresh release settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading feature previews")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if states.isEmpty {
                ContentUnavailableView(
                    "Feature Previews",
                    systemImage: "switch.2",
                    description: Text("No feature previews are available for this device.")
                )
            } else {
                Section("Available Previews") {
                    ForEach(states) { state in
                        ReleaseControlFlagStateRow(state: state) { isEnabled in
                            Task {
                                await updatePreference(isEnabled, for: state)
                            }
                        }
                    }
                }
            }

            ReleaseControlStatusSection(status: providerStatus)
        }
        .navigationTitle("Feature Previews")
        .toolbar {
            Button {
                Task {
                    await refreshStates()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
        }
        .task {
            await loadStates()
        }
        .refreshable {
            await refreshStates()
        }
    }

    @MainActor
    private func loadStates() async {
        isLoading = true
        states = await loader.load(using: releaseControlClient)
        await updateProviderStatus(from: states)
        isLoading = false
    }

    @MainActor
    private func refreshStates() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        if states.isEmpty {
            isLoading = true
        }
        states = await loader.refresh(using: releaseControlClient)
        await updateProviderStatus(from: states)
        isLoading = false
        isRefreshing = false
    }

    @MainActor
    private func updatePreference(_ isEnabled: Bool, for state: ReleaseControlFlagState) async {
        let previousPreference = state.preference
        preferenceStore.setPreference(
            isEnabled ? .optIn : .optOut,
            for: state.key,
            notifiesObservers: false
        )

        if state.key == .authenticationFeature {
            await releaseControlClient.track(isEnabled
                ? .authenticationFeatureOptedIn(
                    launchSource: "feature_previews",
                    previousPreference: previousPreference.rawValue,
                    variationKey: state.variationLabel
                )
                : .authenticationFeatureOptedOut(
                    launchSource: "feature_previews",
                    previousPreference: previousPreference.rawValue,
                    variationKey: state.variationLabel
                )
            )
        }
        states = await loader.refresh(using: releaseControlClient)
        await updateProviderStatus(from: states)
        preferenceStore.postPreferenceDidChange(for: state.key)
    }

    @MainActor
    private func updateProviderStatus(from loadedStates: [ReleaseControlFlagState]) async {
        if let status = loadedStates.first?.providerStatus {
            providerStatus = status
        } else {
            providerStatus = await releaseControlClient.status()
        }
    }
}

private struct ReleaseControlStatusSection: View {
    let status: ReleaseControlStatus?

    var body: some View {
        Section("Release Controls") {
            if let status {
                LabeledContent("Provider", value: status.providerDisplayName)
                LabeledContent("Status", value: status.connectionDisplayName)
                LabeledContent("Environment", value: status.environmentDisplayName)
                LabeledContent("User", value: status.userDisplayName)
                LabeledContent("Datafile", value: status.datafileDisplayName)
            } else {
                LabeledContent("Status", value: "Loading")
            }
        }
        .textSelection(.enabled)
    }
}

private struct ReleaseControlFlagStateRow: View {
    let state: ReleaseControlFlagState
    let onPreferenceChanged: (Bool) -> Void

    @State private var isShowingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    withAnimation(.snappy) {
                        isShowingDetails.toggle()
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.displayName)
                                .font(.headline)

                            if state.stateLabel == "Unavailable" {
                                Text(state.stateLabel)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } icon: {
                        Image(systemName: stateIcon)
                            .foregroundStyle(stateIconStyle)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(state.displayName)
                .accessibilityHint(isShowingDetails ? "Hides feature details" : "Shows feature details")

                Spacer()

                Toggle(
                    state.stateLabel,
                    isOn: Binding(
                        get: { state.preferenceToggleValue },
                        set: { isEnabled in
                            onPreferenceChanged(isEnabled)
                        }
                    )
                )
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if isShowingDetails {
                ReleaseControlFlagStateDetails(state: state)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }

    private var stateIcon: String {
        switch state.stateLabel {
        case "Enabled":
            return "checkmark.circle"
        case "Off":
            return "slash.circle"
        case "Available", "Requested":
            return "switch.2"
        default:
            return "exclamationmark.triangle"
        }
    }

    private var stateIconStyle: Color {
        switch state.stateLabel {
        case "Enabled":
            return .green
        case "Off":
            return .secondary
        case "Available", "Requested":
            return .blue
        default:
            return .orange
        }
    }
}

private struct ReleaseControlFlagStateDetails: View {
    let state: ReleaseControlFlagState

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Key")
                    .foregroundStyle(.secondary)
                Text(state.key.rawValue)
                    .monospaced()
            }

            GridRow {
                Text("Provider")
                    .foregroundStyle(.secondary)
                Text(state.providerStatus.providerDisplayName)
            }

            GridRow {
                Text("Connection")
                    .foregroundStyle(.secondary)
                Text(state.providerConnectionLabel)
            }

            GridRow {
                Text("State")
                    .foregroundStyle(.secondary)
                Text(state.stateLabel)
            }

            GridRow {
                Text("Preference")
                    .foregroundStyle(.secondary)
                Text(state.preference.displayName)
            }

            if let variation = state.variationLabel {
                GridRow {
                    Text("Variation")
                        .foregroundStyle(.secondary)
                    Text(variation)
                }
            }

            GridRow {
                Text("Variables")
                    .foregroundStyle(.secondary)
                EmptyView()
            }

            ForEach(state.variableDetails) { variable in
                GridRow {
                    Text(variable.key)
                        .foregroundStyle(.secondary)
                        .monospaced()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(variable.value)
                            .monospaced()
                        Text(variable.source.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.caption)
        .textSelection(.enabled)

        if let reason = state.fallbackReason, !reason.isEmpty {
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
