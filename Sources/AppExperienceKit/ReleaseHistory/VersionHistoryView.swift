import SwiftUI

public struct VersionHistoryView: View {
    private let presentation: ReleaseHistoryPresentation

    public init(
        releaseHistory: PublicReleaseHistory = .bundled(),
        fallbackHistory: VersionHistory = .bundled()
    ) {
        presentation = ReleaseHistoryPresentation.make(
            publicHistory: releaseHistory,
            fallbackHistory: fallbackHistory
        )
    }

    public init(history: VersionHistory) {
        presentation = ReleaseHistoryPresentation.make(
            publicHistory: PublicReleaseHistory(releases: []),
            fallbackHistory: history
        )
    }

    public var body: some View {
        List {
            if presentation.releases.isEmpty {
                ContentUnavailableView(
                    "No Version History",
                    systemImage: "clock.badge.questionmark",
                    description: Text("Release notes are not available in this build.")
                )
            } else {
                ForEach(presentation.releases) { release in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(release.title)
                                .font(.headline)
                            Text("\(release.tag) - \(release.date)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let summary = release.summary {
                                Text(summary)
                                    .font(.body)
                            }

                            ForEach(release.details, id: \.self) { detail in
                                Label(detail, systemImage: "checkmark.circle")
                                    .font(.body)
                            }

                            if let safetyNote = release.safetyNote {
                                Label(safetyNote, systemImage: "exclamationmark.triangle")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Version \(release.version)")
                    }
                }
            }
        }
        .navigationTitle("Version History")
    }
}
