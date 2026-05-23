import Foundation
import Combine
import SwiftUI

@MainActor
public final class GitHubAuthViewModel: ObservableObject {
    @Published public private(set) var deviceCode: GitHubDeviceCode?
    @Published public private(set) var message: String?
    @Published public private(set) var isWorking = false

    private let tokenStore: GitHubTokenStore
    private let deviceFlowClient: GitHubDeviceFlowClient
    private let identityClient: any GitHubIdentityClient
    private let identityStore: AppIdentityStore

    public init(
        configuration: GitHubFeedbackConfiguration = .mainBundle(),
        tokenStore: GitHubTokenStore = KeychainGitHubTokenStore(),
        httpClient: HTTPClient = URLSessionHTTPClient(),
        identityClient: (any GitHubIdentityClient)? = nil,
        identityStore: AppIdentityStore = AppIdentityStore()
    ) {
        self.tokenStore = tokenStore
        self.deviceFlowClient = GitHubDeviceFlowClient(configuration: configuration, httpClient: httpClient)
        self.identityClient = identityClient ?? GitHubRESTIdentityClient(httpClient: httpClient)
        self.identityStore = identityStore
    }

    public var connectionState: GitHubConnectionState {
        tokenStore.loadToken() == nil ? .disconnected : .connected
    }

    public func startAuthentication() async {
        isWorking = true
        defer { isWorking = false }

        do {
            deviceCode = try await deviceFlowClient.requestDeviceCode()
            message = "Enter the code on GitHub, then return here to finish connecting."
        } catch {
            message = error.localizedDescription
        }
    }

    public func completeAuthentication() async {
        guard let deviceCode else {
            message = "Start GitHub authentication first."
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let token = try await deviceFlowClient.pollForToken(deviceCode: deviceCode.deviceCode)
            let identity = try await identityClient.fetchAuthenticatedUser(token: token)
            tokenStore.saveToken(token)
            identityStore.linkGitHubUser(id: identity.id, login: identity.login)
            self.deviceCode = nil
            message = "GitHub is connected."
        } catch {
            message = error.localizedDescription
        }
    }

    public func disconnect() {
        tokenStore.deleteToken()
        identityStore.disconnectGitHub()
        deviceCode = nil
        message = "GitHub is disconnected."
    }
}
