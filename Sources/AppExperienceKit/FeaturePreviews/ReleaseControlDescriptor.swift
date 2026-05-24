import Foundation

public struct ReleaseControlDescriptor: Identifiable, Sendable, Equatable, Hashable {
    public let key: String
    public let displayName: String

    public init(key: String, displayName: String) {
        self.key = key
        self.displayName = displayName
    }

    public var id: String {
        key
    }
}

public extension ReleaseControlDescriptor {
    static var packageDefaults: [ReleaseControlDescriptor] {
        ReleaseControlKey.allCases.map(\.descriptor)
    }
}

public extension ReleaseControlKey {
    var descriptor: ReleaseControlDescriptor {
        ReleaseControlDescriptor(key: rawValue, displayName: displayName)
    }
}
