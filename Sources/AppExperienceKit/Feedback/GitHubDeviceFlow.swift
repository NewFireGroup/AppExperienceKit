import Foundation

public struct GitHubDeviceCode: Decodable, Equatable, Sendable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURI: URL
    public var expiresIn: Int
    public var interval: Int

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

public enum GitHubDeviceFlowError: Error, Equatable, LocalizedError {
    case missingClientID
    case authorizationPending
    case accessDenied
    case expiredToken
    case slowDown
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "GitHub App client id is not configured."
        case .authorizationPending:
            return "GitHub authorization is still pending."
        case .accessDenied:
            return "GitHub authorization was denied."
        case .expiredToken:
            return "GitHub authorization expired."
        case .slowDown:
            return "GitHub asked the app to slow down polling."
        case .unexpectedResponse(let message):
            return message
        }
    }
}

@MainActor
public struct GitHubDeviceFlowClient {
    private let configuration: GitHubFeedbackConfiguration
    private let httpClient: HTTPClient
    private let decoder = JSONDecoder()

    public init(
        configuration: GitHubFeedbackConfiguration,
        httpClient: HTTPClient = URLSessionHTTPClient()
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func requestDeviceCode() async throws -> GitHubDeviceCode {
        guard let clientID = configuration.clientID else {
            throw GitHubDeviceFlowError.missingClientID
        }

        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["client_id": clientID])

        let (data, response) = try await httpClient.data(for: request)
        guard response.statusCode == 200 else {
            throw GitHubDeviceFlowError.unexpectedResponse("GitHub device-code request failed.")
        }
        return try decoder.decode(GitHubDeviceCode.self, from: data)
    }

    public func pollForToken(deviceCode: String) async throws -> String {
        guard let clientID = configuration.clientID else {
            throw GitHubDeviceFlowError.missingClientID
        }

        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])

        let (data, response) = try await httpClient.data(for: request)
        guard response.statusCode == 200 else {
            throw GitHubDeviceFlowError.unexpectedResponse("GitHub token request failed.")
        }

        if let error = try? decoder.decode(GitHubDeviceFlowErrorResponse.self, from: data) {
            switch error.error {
            case "authorization_pending":
                throw GitHubDeviceFlowError.authorizationPending
            case "access_denied":
                throw GitHubDeviceFlowError.accessDenied
            case "expired_token":
                throw GitHubDeviceFlowError.expiredToken
            case "slow_down":
                throw GitHubDeviceFlowError.slowDown
            default:
                throw GitHubDeviceFlowError.unexpectedResponse(error.errorDescription ?? error.error)
            }
        }

        let token = try decoder.decode(GitHubDeviceFlowTokenResponse.self, from: data)
        return token.accessToken
    }

    private func formBody(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}

private struct GitHubDeviceFlowTokenResponse: Decodable {
    var accessToken: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct GitHubDeviceFlowErrorResponse: Decodable {
    var error: String
    var errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
