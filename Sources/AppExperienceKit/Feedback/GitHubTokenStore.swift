import Foundation
import Security

public final class KeychainGitHubTokenStore: GitHubTokenStore {
    private let service: String
    private let account: String

    public init(
        service: String = "dev.boster.expanse.planner.github",
        account: String = "early-adopter-feedback"
    ) {
        self.service = service
        self.account = account
    }

    public func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func saveToken(_ token: String) {
        deleteToken()
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    public func deleteToken() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
