import Foundation

public struct PublicReleaseHistory: Decodable, Equatable, Sendable {
    public var releases: [PublicReleaseHistoryRelease]

    public var latest: PublicReleaseHistoryRelease? {
        releases.first
    }

    public static func decode(_ data: Data) throws -> PublicReleaseHistory {
        try JSONDecoder().decode(PublicReleaseHistory.self, from: data)
    }

    public static func bundled(bundle: Bundle = .main) -> PublicReleaseHistory {
        guard let url = bundle.url(forResource: "ReleaseHistory", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let history = try? decode(data) else {
            return PublicReleaseHistory(releases: [])
        }

        return history
    }

    public func aboutDisplayVersion(
        fallbackHistory: VersionHistory,
        bundleShortVersion: String?
    ) -> String {
        if let latestVersion = latest?.version, !latestVersion.isEmpty {
            return latestVersion
        }

        return fallbackHistory.aboutDisplayVersion(bundleShortVersion: bundleShortVersion)
    }
}

public struct PublicReleaseHistoryRelease: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { tag }
    public var version: String
    public var tag: String
    public var date: String
    public var title: String
    public var summary: String
    public var highlights: [String]
    public var safetyNote: String?
    public var sourceIssues: [Int]?
    public var betaTags: [String]?
}

public struct ReleaseHistoryPresentation: Equatable, Sendable {
    public var releases: [ReleaseHistoryPresentationRelease]

    public static func make(
        publicHistory: PublicReleaseHistory,
        fallbackHistory: VersionHistory
    ) -> ReleaseHistoryPresentation {
        if !publicHistory.releases.isEmpty {
            return ReleaseHistoryPresentation(
                releases: publicHistory.releases.map {
                    ReleaseHistoryPresentationRelease(publicRelease: $0)
                }
            )
        }

        return ReleaseHistoryPresentation(
            releases: fallbackHistory.releases.map {
                ReleaseHistoryPresentationRelease(internalRelease: $0)
            }
        )
    }
}

public struct ReleaseHistoryPresentationRelease: Equatable, Identifiable, Sendable {
    public var id: String { tag }
    public var version: String
    public var tag: String
    public var date: String
    public var title: String
    public var summary: String?
    public var details: [String]
    public var safetyNote: String?

    init(publicRelease: PublicReleaseHistoryRelease) {
        version = publicRelease.version
        tag = publicRelease.tag
        date = publicRelease.date
        title = publicRelease.title
        summary = publicRelease.summary
        details = publicRelease.highlights
        safetyNote = publicRelease.safetyNote
    }

    init(internalRelease: VersionHistoryRelease) {
        version = internalRelease.version
        tag = internalRelease.tag
        date = internalRelease.date
        title = internalRelease.title
        summary = nil
        details = internalRelease.changes
        safetyNote = nil
    }
}
