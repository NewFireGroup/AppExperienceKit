import Foundation

public struct GitHubUserIdentity: Decodable, Equatable, Sendable {
    public var id: Int
    public var login: String

    public init(id: Int, login: String) {
        self.id = id
        self.login = login
    }
}

public enum GitHubIdentityClientError: Error, Equatable, LocalizedError {
    case authenticationRequired
    case requestFailed(Int, String)

    public var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "GitHub authentication is required."
        case .requestFailed(let statusCode, let message):
            return "GitHub identity lookup failed (\(statusCode)): \(message)"
        }
    }
}

@MainActor
public protocol GitHubIdentityClient {
    func fetchAuthenticatedUser(token: String) async throws -> GitHubUserIdentity
}

public struct GitHubRESTIdentityClient: GitHubIdentityClient {
    private let httpClient: HTTPClient
    private let decoder: JSONDecoder

    public init(
        httpClient: HTTPClient = URLSessionHTTPClient(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.httpClient = httpClient
        self.decoder = decoder
    }

    public func fetchAuthenticatedUser(token: String) async throws -> GitHubUserIdentity {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubIdentityClientError.authenticationRequired
        }

        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await httpClient.data(for: request)
        switch response.statusCode {
        case 200..<300:
            return try decoder.decode(GitHubUserIdentity.self, from: data)
        case 401, 403:
            throw GitHubIdentityClientError.authenticationRequired
        default:
            let message = (try? decoder.decode(GitHubIdentityErrorResponse.self, from: data).message) ?? "Unknown error"
            throw GitHubIdentityClientError.requestFailed(response.statusCode, message)
        }
    }
}

private struct GitHubIdentityErrorResponse: Decodable {
    var message: String
}
