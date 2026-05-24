import Foundation

public struct AppExperienceHostConfiguration: Equatable, Sendable {
    public var productName: String
    public var displayName: String
    public var loadingTitle: String
    public var lockedTitle: String
    public var localAuthenticationReason: String

    public init(
        productName: String = "App",
        displayName: String? = nil,
        loadingTitle: String? = nil,
        lockedTitle: String? = nil,
        localAuthenticationReason: String? = nil
    ) {
        let normalizedProductName = Self.normalized(productName) ?? "App"
        let normalizedDisplayName = Self.normalized(displayName) ?? normalizedProductName

        self.productName = normalizedProductName
        self.displayName = normalizedDisplayName
        self.loadingTitle = Self.normalized(loadingTitle) ?? "Loading \(normalizedDisplayName)..."
        self.lockedTitle = Self.normalized(lockedTitle) ?? "\(normalizedDisplayName) Locked"
        self.localAuthenticationReason = Self.normalized(localAuthenticationReason) ?? "Unlock \(normalizedDisplayName)."
    }

    public static func mainBundle(
        bundle: Bundle = .main,
        fallbackDisplayName: String = "App"
    ) -> AppExperienceHostConfiguration {
        let displayName = normalized(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        let productName = normalized(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)

        return AppExperienceHostConfiguration(
            productName: productName ?? displayName ?? fallbackDisplayName,
            displayName: displayName ?? productName ?? fallbackDisplayName
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
