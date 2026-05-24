import Foundation

public struct GitHubFeedbackConfiguration: Equatable, Sendable {
    public var clientID: String?
    public var owner: String
    public var repo: String

    public init(clientID: String?, owner: String, repo: String) {
        self.clientID = Self.normalized(clientID)
        self.owner = Self.normalized(owner) ?? ""
        self.repo = Self.normalized(repo) ?? ""
    }

    public var isIssueSubmissionConfigured: Bool {
        !owner.isEmpty && !repo.isEmpty
    }

    public static func mainBundle(
        bundle: Bundle = .main,
        defaultOwner: String? = nil,
        defaultRepo: String? = nil
    ) -> GitHubFeedbackConfiguration {
        GitHubFeedbackConfiguration(
            clientID: bundle.infoDictionary?["GitHubFeedbackClientID"] as? String,
            owner: Self.normalized(bundle.infoDictionary?["GitHubFeedbackOwner"] as? String) ??
                Self.normalized(defaultOwner) ?? "",
            repo: Self.normalized(bundle.infoDictionary?["GitHubFeedbackRepo"] as? String) ??
                Self.normalized(defaultRepo) ?? ""
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return nil
        }
        return trimmed
    }
}
