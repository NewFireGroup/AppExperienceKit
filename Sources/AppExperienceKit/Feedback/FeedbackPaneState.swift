import SwiftUI

public struct FeedbackPaneColumnWidth: Equatable, Sendable {
    public static let compactPhoneWidth: CGFloat = 320
    public let minimum: CGFloat
    public let ideal: CGFloat
    public let maximum: CGFloat

    public init(minimum: CGFloat, ideal: CGFloat, maximum: CGFloat) {
        self.minimum = minimum
        self.ideal = ideal
        self.maximum = maximum
    }
}

public struct FeedbackPaneState: Equatable {
    public static let feedbackColumnWidth = FeedbackPaneColumnWidth(
        minimum: FeedbackPaneColumnWidth.compactPhoneWidth,
        ideal: FeedbackPaneColumnWidth.compactPhoneWidth,
        maximum: FeedbackPaneColumnWidth.compactPhoneWidth
    )

    public private(set) var launchContext: FeedbackLaunchContext?

    public init(launchContext: FeedbackLaunchContext? = nil) {
        self.launchContext = launchContext
    }

    public var isPresented: Bool {
        launchContext != nil
    }

    public var columnVisibility: NavigationSplitViewVisibility {
        .doubleColumn
    }

    public mutating func open(_ launchContext: FeedbackLaunchContext) {
        self.launchContext = launchContext
    }

    public mutating func close() {
        launchContext = nil
    }
}

public struct FeedbackPaneOpener: Sendable {
    private let handler: @MainActor @Sendable (FeedbackLaunchContext) -> Bool

    public init(_ handler: @escaping @MainActor @Sendable (FeedbackLaunchContext) -> Bool) {
        self.handler = handler
    }

    @MainActor
    @discardableResult
    public func open(_ launchContext: FeedbackLaunchContext) -> Bool {
        handler(launchContext)
    }
}

private struct FeedbackPaneOpenerKey: EnvironmentKey {
    static let defaultValue = FeedbackPaneOpener { _ in false }
}

public extension EnvironmentValues {
    var feedbackPaneOpener: FeedbackPaneOpener {
        get { self[FeedbackPaneOpenerKey.self] }
        set { self[FeedbackPaneOpenerKey.self] = newValue }
    }
}

public extension View {
    func feedbackPaneOpener(_ opener: FeedbackPaneOpener) -> some View {
        environment(\.feedbackPaneOpener, opener)
    }
}
