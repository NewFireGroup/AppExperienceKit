import Foundation
import Testing

@testable import AppExperienceKit

struct ReleaseHistoryPackageTests {
    @Test
    func publicReleaseHistoryDecodesUserFacingNotes() throws {
        let history = try PublicReleaseHistory.decode(Self.publicFixtureData)

        #expect(history.releases.map(\.tag) == ["v1.0.15"])
        #expect(history.latest?.version == "1.0.15")
        #expect(history.latest?.summary == "Feature Previews make early features easier to try.")
        #expect(history.latest?.highlights.first == "See which early features are available on your device.")
        #expect(history.latest?.safetyNote == "Export your data before trying previews.")
        #expect(history.latest?.sourceIssues == [121, 142, 144, 153, 156])
        #expect(history.latest?.betaTags == ["beta-v1.0.15-01"])
    }

    @Test
    func releaseHistoryPresentationPrefersPublicNotesOverInternalNotes() throws {
        let publicHistory = try PublicReleaseHistory.decode(Self.publicFixtureData)
        let internalHistory = try VersionHistory.decode(Self.internalFixtureData)
        let presentation = ReleaseHistoryPresentation.make(
            publicHistory: publicHistory,
            fallbackHistory: internalHistory
        )

        #expect(presentation.releases.map(\.tag) == ["v1.0.15"])
        #expect(presentation.releases.first?.title == "Feature Previews")
        #expect(presentation.releases.first?.summary == "Feature Previews make early features easier to try.")
        #expect(presentation.releases.first?.details == [
            "See which early features are available on your device.",
            "Turn previews on or off for this device."
        ])
        #expect(presentation.releases.first?.safetyNote == "Export your data before trying previews.")
    }

    @Test
    func releaseHistoryPresentationFallsBackToInternalHistory() throws {
        let internalHistory = try VersionHistory.decode(Self.internalFixtureData)
        let presentation = ReleaseHistoryPresentation.make(
            publicHistory: PublicReleaseHistory(releases: []),
            fallbackHistory: internalHistory
        )

        #expect(presentation.releases.map(\.tag) == ["v1.0.2", "v1.0.1"])
        #expect(presentation.releases.first?.summary == nil)
        #expect(presentation.releases.first?.details.first == "Review version history from About.")
    }

    @Test
    func aboutDisplayVersionUsesPublicThenInternalThenBundleFallbacks() throws {
        let publicHistory = try PublicReleaseHistory.decode(Self.publicFixtureData)
        let internalHistory = try VersionHistory.decode(Self.internalFixtureData)

        #expect(
            publicHistory.aboutDisplayVersion(
                fallbackHistory: internalHistory,
                bundleShortVersion: "1.0"
            ) == "1.0.15"
        )
        #expect(
            PublicReleaseHistory(releases: []).aboutDisplayVersion(
                fallbackHistory: internalHistory,
                bundleShortVersion: "1.0"
            ) == "1.0.2"
        )
        #expect(VersionHistory(releases: []).aboutDisplayVersion(bundleShortVersion: "1.0") == "1.0")
        #expect(VersionHistory(releases: []).aboutDisplayVersion(bundleShortVersion: nil) == "Unknown")
    }

    private static let internalFixtureData = Data(
        """
        {
          "releases": [
            {
              "version": "1.0.2",
              "tag": "v1.0.2",
              "date": "2026-05-10",
              "title": "Release history and Document Workflow foundation",
              "changes": [
                "Review version history from About.",
                "Confirm Document Workflow foundation remains available for follow-up work."
              ]
            },
            {
              "version": "1.0.1",
              "tag": "v1.0.1",
              "date": "2026-05-09",
              "title": "Xcode Cloud release script hardening",
              "changes": [
                "Validate release tag versioning."
              ]
            }
          ]
        }
        """.utf8
    )

    private static let publicFixtureData = Data(
        """
        {
          "releases": [
            {
              "version": "1.0.15",
              "tag": "v1.0.15",
              "date": "2026-05-12",
              "title": "Feature Previews",
              "summary": "Feature Previews make early features easier to try.",
              "highlights": [
                "See which early features are available on your device.",
                "Turn previews on or off for this device."
              ],
              "safetyNote": "Export your data before trying previews.",
              "sourceIssues": [121, 142, 144, 153, 156],
              "betaTags": ["beta-v1.0.15-01"]
            }
          ]
        }
        """.utf8
    )
}
