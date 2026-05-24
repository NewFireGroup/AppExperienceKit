import Foundation

#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

public enum LocalAuthenticationOutcome: Equatable, Sendable {
    case success
    case canceled
    case failed(String)
    case unavailable(String)

    public var lockedReason: String? {
        switch self {
        case .success:
            return nil
        case .canceled:
            return "Authentication was canceled."
        case .failed(let message),
             .unavailable(let message):
            return message
        }
    }
}

public protocol LocalAuthenticating: Sendable {
    func authenticate(reason: String) async -> LocalAuthenticationOutcome
}

public struct SystemLocalAuthenticator: LocalAuthenticating {
    public init() {
    }

    public func authenticate(reason: String) async -> LocalAuthenticationOutcome {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(error?.localizedDescription ?? "Local authentication is unavailable.")
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: .success)
                    return
                }

                if let laError = error as? LAError,
                   [.userCancel, .appCancel, .systemCancel].contains(laError.code) {
                    continuation.resume(returning: .canceled)
                    return
                }

                continuation.resume(returning: .failed(error?.localizedDescription ?? "Authentication failed."))
            }
        }
        #else
        return .unavailable("Local authentication is unavailable on this platform.")
        #endif
    }
}

public enum AppLockAccessState: Equatable, Sendable {
    case unlocked
    case locked(reason: String)
}

public final class AppLockController: @unchecked Sendable {
    private let identityStore: AppIdentityStore
    private let authenticator: any LocalAuthenticating

    public init(
        identityStore: AppIdentityStore = AppIdentityStore(),
        authenticator: any LocalAuthenticating = SystemLocalAuthenticator()
    ) {
        self.identityStore = identityStore
        self.authenticator = authenticator
    }

    public func evaluateLaunchAccess(
        decision: ReleaseControlDecision,
        preference: ReleaseControlPreference,
        reason: String = AppExperienceHostConfiguration().localAuthenticationReason
    ) async -> AppLockAccessState {
        guard decision.isAuthenticationAppLockAvailable(preference: preference),
              decision.authenticationAppLockMode == .launchOnly,
              identityStore.isAppLockEnabled
        else {
            return .unlocked
        }

        let outcome = await authenticator.authenticate(reason: reason)
        if outcome == .success {
            return .unlocked
        }

        return .locked(reason: outcome.lockedReason ?? "Authentication failed.")
    }
}
