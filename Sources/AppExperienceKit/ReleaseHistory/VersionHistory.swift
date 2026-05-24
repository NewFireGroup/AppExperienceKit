import Foundation

public struct VersionHistory: Decodable, Equatable, Sendable {
    public var releases: [VersionHistoryRelease]

    public var latest: VersionHistoryRelease? {
        releases.first
    }

    public static func decode(_ data: Data) throws -> VersionHistory {
        try JSONDecoder().decode(VersionHistory.self, from: data)
    }

    public static func bundled(bundle: Bundle = .main) -> VersionHistory {
        guard let url = bundle.url(forResource: "VersionHistory", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let history = try? decode(data) else {
            return VersionHistory(releases: [])
        }

        return history
    }

    public func aboutDisplayVersion(bundleShortVersion: String?) -> String {
        if let latestVersion = latest?.version, !latestVersion.isEmpty {
            return latestVersion
        }

        guard let bundleShortVersion, !bundleShortVersion.isEmpty else {
            return "Unknown"
        }

        return bundleShortVersion
    }

    public func testFlightNotes() -> String {
        guard let latest else {
            return "No release history is available.\n"
        }

        var lines: [String] = [
            latest.title,
            "Version \(latest.version) (\(latest.tag)) - \(latest.date)",
            "",
            "What to Test"
        ]

        lines.append(contentsOf: latest.changes.map { "- \($0)" })
        lines.append("")
        lines.append("Version History")
        lines.append(contentsOf: releases.map { "- \($0.tag) - \($0.title)" })

        return lines.joined(separator: "\n") + "\n"
    }
}

public struct VersionHistoryRelease: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { tag }
    public var version: String
    public var tag: String
    public var date: String
    public var title: String
    public var changes: [String]
}
