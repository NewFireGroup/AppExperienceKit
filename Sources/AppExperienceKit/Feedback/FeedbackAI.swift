import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum FeedbackAIAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    public var displayName: String {
        switch self {
        case .available:
            return "available"
        case .unavailable(let reason):
            return "unavailable: \(reason)"
        }
    }
}

public enum FeedbackAppleIntelligenceSettingsPlatform: Sendable {
    case iOS
    case mac

    public static var current: FeedbackAppleIntelligenceSettingsPlatform {
        #if os(macOS)
        return .mac
        #else
        return .iOS
        #endif
    }

    var settingsPath: String {
        switch self {
        case .iOS:
            return "Settings > Apple Intelligence & Siri"
        case .mac:
            return "System Settings > Apple Intelligence & Siri"
        }
    }
}

public enum FeedbackAIAssistSettings {
    public static func showsSettingsToggle(decision: ReleaseControlDecision) -> Bool {
        decision.allowsFeedbackAIAssist
    }

    public static func canEnable(availability: FeedbackAIAvailability) -> Bool {
        availability == .available
    }

    public static func showsToolbarButton(
        decision: ReleaseControlDecision,
        isUserEnabled: Bool,
        availability: FeedbackAIAvailability
    ) -> Bool {
        showsSettingsToggle(decision: decision) &&
        isUserEnabled &&
        canEnable(availability: availability)
    }

    public static func startsFeedbackWithAIAssist(
        decision: ReleaseControlDecision,
        isUserEnabled: Bool,
        isStartWithAssistEnabled: Bool,
        availability: FeedbackAIAvailability,
        launchSurface: FeedbackAIAssistLaunchSurface,
        isEditingDraft: Bool,
        hasMeaningfulContent: Bool
    ) -> Bool {
        launchSurface.allowsStartWithAssist &&
        isStartWithAssistEnabled &&
        !isEditingDraft &&
        !hasMeaningfulContent &&
        showsToolbarButton(
            decision: decision,
            isUserEnabled: isUserEnabled,
            availability: availability
        )
    }

    public static func disabledMessage(
        for availability: FeedbackAIAvailability,
        platform: FeedbackAppleIntelligenceSettingsPlatform = .current
    ) -> String? {
        guard !canEnable(availability: availability) else { return nil }

        return "Apple Intelligence is currently disabled. To use this feature, open \(platform.settingsPath) and turn on Apple Intelligence."
    }
}

public enum FeedbackAIAssistLaunchSurface: Equatable, Sendable {
    case phoneSheet
    case splitPane
    case standaloneWindow

    var allowsStartWithAssist: Bool {
        switch self {
        case .phoneSheet, .splitPane:
            return true
        case .standaloneWindow:
            return false
        }
    }
}

public enum FeedbackAIAssistMode: Equatable, Sendable {
    case aiAssisted
    case manualFallback

    public var telemetryResult: String {
        switch self {
        case .aiAssisted:
            return "ai_assisted"
        case .manualFallback:
            return "manual_fallback"
        }
    }
}

public struct FeedbackAIAssistResult {
    public var mode: FeedbackAIAssistMode
    public var draft: FeedbackDraft
    public var reason: String?

    public init(mode: FeedbackAIAssistMode, draft: FeedbackDraft, reason: String? = nil) {
        self.mode = mode
        self.draft = draft
        self.reason = reason
    }
}

@MainActor
public protocol FeedbackAIClient {
    func availability() -> FeedbackAIAvailability
    func assist(message: String, existingDraft: FeedbackDraft) async throws -> FeedbackAIAssistResult
}

@MainActor
public struct FeedbackAICoordinator {
    private let client: FeedbackAIClient

    public init(client: FeedbackAIClient) {
        self.client = client
    }

    public func availability() -> FeedbackAIAvailability {
        client.availability()
    }

    public func assist(message: String, existingDraft: FeedbackDraft) async throws -> FeedbackAIAssistResult {
        switch client.availability() {
        case .available:
            return try await client.assist(message: message, existingDraft: existingDraft)
        case .unavailable(let reason):
            return FeedbackAIAssistResult(
                mode: .manualFallback,
                draft: existingDraft,
                reason: reason
            )
        }
    }
}

@MainActor
enum FeedbackAIAssistResultApplier {
    static func apply(
        _ result: FeedbackAIAssistResult,
        store: FeedbackDraftStore
    ) throws -> FeedbackFormSnapshot {
        result.draft.source = result.mode == .aiAssisted ? .aiAssisted : .manual
        try store.save(result.draft)
        return FeedbackFormSnapshot(draft: result.draft)
    }
}

@MainActor
public struct FeedbackAIAssistSessionUpdate {
    let result: FeedbackAIAssistResult
    public let draft: FeedbackDraft
    public let snapshot: FeedbackFormSnapshot
}

@MainActor
public enum FeedbackAIAssistSession {
    public static func apply(
        message: String,
        snapshot: FeedbackFormSnapshot,
        currentDraft: FeedbackDraft?,
        store: FeedbackDraftStore,
        diagnostics: FeedbackDiagnostics,
        client: any FeedbackAIClient
    ) async throws -> FeedbackAIAssistSessionUpdate {
        let draft: FeedbackDraft
        if let currentDraft {
            draft = currentDraft
            draft.diagnostics = diagnostics
        } else {
            draft = try store.createDraft(
                category: snapshot.category,
                source: snapshot.source,
                diagnostics: diagnostics
            )
        }

        snapshot.apply(to: draft)
        try store.save(draft)

        let coordinator = FeedbackAICoordinator(client: client)
        let result = try await coordinator.assist(message: message, existingDraft: draft)
        try Task.checkCancellation()
        let appliedSnapshot = try FeedbackAIAssistResultApplier.apply(result, store: store)

        return FeedbackAIAssistSessionUpdate(
            result: result,
            draft: result.draft,
            snapshot: appliedSnapshot
        )
    }
}

public struct ManualOnlyFeedbackAIClient: FeedbackAIClient {
    private let reason: String

    public init(reason: String = "AI assistance is unavailable") {
        self.reason = reason
    }

    public func availability() -> FeedbackAIAvailability {
        .unavailable(reason)
    }

    public func assist(message: String, existingDraft: FeedbackDraft) async throws -> FeedbackAIAssistResult {
        FeedbackAIAssistResult(mode: .manualFallback, draft: existingDraft, reason: reason)
    }
}

public enum FeedbackAIClientFactory {
    @MainActor
    public static func makeClient() -> any FeedbackAIClient {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return FoundationModelsFeedbackAIClient()
        }
        #endif
        return ManualOnlyFeedbackAIClient(reason: "Apple Foundation Models are unavailable on this platform")
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
public struct FoundationModelsFeedbackAIClient: FeedbackAIClient {
    private let model: SystemLanguageModel

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    public func availability() -> FeedbackAIAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence is not enabled")
        case .unavailable(.deviceNotEligible):
            return .unavailable("This device is not eligible for Apple Intelligence")
        case .unavailable(.modelNotReady):
            return .unavailable("The local Apple Intelligence model is not ready")
        @unknown default:
            return .unavailable("Apple Intelligence is unavailable")
        }
    }

    public func assist(message: String, existingDraft: FeedbackDraft) async throws -> FeedbackAIAssistResult {
        let session = LanguageModelSession(
            model: model,
            instructions: """
            Help an early adopter write useful app feedback. Ask concise follow-up questions when information is missing, and draft safe GitHub issue fields. Do not request household names, amounts, exported files, logs, or private financial details.
            """
        )
        let response = try await session.respond(
            to: """
            Convert this rough feedback into JSON with keys title, summary, stepsToReproduce, expectedBehavior, actualBehavior, additionalContext, category.

            Feedback:
            \(message)
            """
        )

        FeedbackAISuggestion.apply(response.content, to: existingDraft)
        existingDraft.source = .aiAssisted
        return FeedbackAIAssistResult(mode: .aiAssisted, draft: existingDraft)
    }
}
#endif

struct FeedbackAISuggestion: Decodable {
    var title: String?
    var summary: String?
    var stepsToReproduce: String?
    var expectedBehavior: String?
    var actualBehavior: String?
    var additionalContext: String?
    var category: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        title = Self.decodeString(from: container, keys: ["title"])
        summary = Self.decodeString(from: container, keys: ["summary"])
        stepsToReproduce = Self.decodeString(from: container, keys: ["stepsToReproduce", "steps_to_reproduce"])
        expectedBehavior = Self.decodeString(from: container, keys: ["expectedBehavior", "expected_behavior"])
        actualBehavior = Self.decodeString(from: container, keys: ["actualBehavior", "actual_behavior"])
        additionalContext = Self.decodeString(from: container, keys: ["additionalContext", "additional_context"])
        category = Self.decodeString(from: container, keys: ["category"])
    }

    static func apply(_ content: String, to draft: FeedbackDraft) {
        guard let suggestion = decode(from: content) else {
            if draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.summary = content
            }
            return
        }

        if let category = suggestion.category.flatMap(normalizedCategory(from:)) {
            draft.category = category
        }
        draft.title = suggestion.title ?? draft.title
        draft.summary = suggestion.summary ?? draft.summary
        draft.stepsToReproduce = suggestion.stepsToReproduce ?? draft.stepsToReproduce
        draft.expectedBehavior = suggestion.expectedBehavior ?? draft.expectedBehavior
        draft.actualBehavior = suggestion.actualBehavior ?? draft.actualBehavior
        draft.additionalContext = suggestion.additionalContext ?? draft.additionalContext
    }

    private static func decode(from content: String) -> FeedbackAISuggestion? {
        for candidate in jsonCandidates(from: content) {
            guard let data = candidate.data(using: .utf8),
                  let suggestion = try? JSONDecoder().decode(FeedbackAISuggestion.self, from: data) else {
                continue
            }
            return suggestion
        }

        return nil
    }

    private static func decodeString(
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let codingKey = DynamicCodingKey(stringValue: key),
                  let value = try? container.decodeIfPresent(String.self, forKey: codingKey) else {
                continue
            }
            return value
        }

        return nil
    }

    private static func normalizedCategory(from value: String) -> FeedbackCategory? {
        if let category = FeedbackCategory(rawValue: value) {
            return category
        }

        let normalizedValue = normalize(value)
        return FeedbackCategory.allCases.first { category in
            normalize(category.rawValue) == normalizedValue ||
            normalize(category.displayName) == normalizedValue ||
            normalize(category.telemetryValue) == normalizedValue
        }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func jsonCandidates(from content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [trimmed]

        if let fenced = unfencedJSON(from: trimmed) {
            candidates.append(fenced)
        }

        if let extracted = extractJSONObject(from: trimmed) {
            candidates.append(extracted)
        }

        return candidates
    }

    private static func unfencedJSON(from content: String) -> String? {
        guard content.hasPrefix("```") else { return nil }

        var lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return nil }

        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }

        let unfenced = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return unfenced.isEmpty ? nil : unfenced
    }

    private static func extractJSONObject(from content: String) -> String? {
        guard let start = content.firstIndex(of: "{") else { return nil }

        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for index in content[start...].indices {
            let character = content[index]

            if isEscaped {
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "\"" {
                isInsideString.toggle()
                continue
            }

            guard !isInsideString else { continue }

            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(content[start...index])
                }
            }
        }

        return nil
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
