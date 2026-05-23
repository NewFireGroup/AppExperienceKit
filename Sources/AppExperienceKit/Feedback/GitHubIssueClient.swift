import Foundation

public enum GitHubIssueClientError: Error, Equatable, LocalizedError {
    case authenticationRequired
    case missingIssueURL
    case requestFailed(Int, String)

    public var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "GitHub authentication is required."
        case .missingIssueURL:
            return "GitHub did not return an issue URL."
        case let .requestFailed(statusCode, message):
            return "GitHub issue creation failed (\(statusCode)): \(message)"
        }
    }
}

@MainActor
public protocol GitHubIssueClient {
    func createIssue(_ payload: GitHubIssuePayload, token: String) async throws -> URL
}

public struct GitHubIssuePayload: Encodable, Equatable, Sendable {
    public var owner: String
    public var repo: String
    public var title: String
    public var body: String
    public var labels: [String]

    public init(owner: String, repo: String, title: String, body: String, labels: [String]) {
        self.owner = owner
        self.repo = repo
        self.title = title
        self.body = body
        self.labels = labels
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case body
        case labels
    }
}

public struct GitHubRESTIssueClient: GitHubIssueClient {
    private let httpClient: HTTPClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        httpClient: HTTPClient = URLSessionHTTPClient(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.httpClient = httpClient
        self.encoder = encoder
        self.decoder = decoder
    }

    public func createIssue(_ payload: GitHubIssuePayload, token: String) async throws -> URL {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubIssueClientError.authenticationRequired
        }

        let url = URL(string: "https://api.github.com/repos/\(payload.owner)/\(payload.repo)/issues")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await httpClient.data(for: request)
        switch response.statusCode {
        case 200..<300:
            let response = try decoder.decode(CreateIssueResponse.self, from: data)
            guard let url = URL(string: response.htmlURL) else {
                throw GitHubIssueClientError.missingIssueURL
            }
            return url
        case 401, 403:
            throw GitHubIssueClientError.authenticationRequired
        default:
            let message = (try? decoder.decode(GitHubErrorResponse.self, from: data).message) ?? "Unknown error"
            throw GitHubIssueClientError.requestFailed(response.statusCode, message)
        }
    }
}

private struct CreateIssueResponse: Decodable {
    var htmlURL: String

    private enum CodingKeys: String, CodingKey {
        case htmlURL = "html_url"
    }
}

private struct GitHubErrorResponse: Decodable {
    var message: String
}
