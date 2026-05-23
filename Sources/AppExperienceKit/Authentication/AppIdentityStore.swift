import Foundation

public enum AppAuthState: String, Equatable, Sendable {
    case anonymous
    case githubLinked = "github_linked"
}

public struct GitHubLinkedIdentity: Codable, Equatable, Sendable {
    public var id: Int
    public var login: String
    public var linkedAt: Date
    public var isCredentialStale: Bool

    public init(id: Int, login: String, linkedAt: Date, isCredentialStale: Bool = false) {
        self.id = id
        self.login = login
        self.linkedAt = linkedAt
        self.isCredentialStale = isCredentialStale
    }
}

public final class AppIdentityStore: @unchecked Sendable {
    public static let appLockEnabledKey = "authentication.appLock.enabled"
    private static let githubIdentityKey = "authentication.github.identity"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public var authState: AppAuthState {
        linkedGitHubIdentity == nil ? .anonymous : .githubLinked
    }

    public var isAppLockEnabled: Bool {
        defaults.bool(forKey: Self.appLockEnabledKey)
    }

    public var linkedGitHubIdentity: GitHubLinkedIdentity? {
        guard let data = defaults.data(forKey: Self.githubIdentityKey) else {
            return nil
        }

        return try? decoder.decode(GitHubLinkedIdentity.self, from: data)
    }

    public func setAppLockEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.appLockEnabledKey)
    }

    public func linkGitHubUser(id: Int, login: String, linkedAt: Date = Date()) {
        saveGitHubIdentity(GitHubLinkedIdentity(id: id, login: login, linkedAt: linkedAt))
    }

    public func markGitHubCredentialStale() {
        guard var identity = linkedGitHubIdentity else {
            return
        }

        identity.isCredentialStale = true
        saveGitHubIdentity(identity)
    }

    public func disconnectGitHub() {
        defaults.removeObject(forKey: Self.githubIdentityKey)
    }

    private func saveGitHubIdentity(_ identity: GitHubLinkedIdentity) {
        guard let data = try? encoder.encode(identity) else {
            return
        }

        defaults.set(data, forKey: Self.githubIdentityKey)
    }
}
