import Foundation
import SwiftData

@MainActor
public final class FeedbackDraftStore {
    public static let didResetNotification = Notification.Name("FeedbackDraftStore.didReset")
    private static let directoryName = "Feedback"
    private static let storeFileName = "feedback.sqlite"

    public let container: ModelContainer
    private let context: ModelContext

    public init(container: ModelContainer) {
        self.container = container
        self.context = ModelContext(container)
    }

    public static func live(
        fileManager: FileManager = .default
    ) throws -> FeedbackDraftStore {
        let directoryURL = try ensureFeedbackDirectory(fileManager: fileManager)

        let configuration = ModelConfiguration(
            schema: Schema(FeedbackSchema.all),
            url: directoryURL.appendingPathComponent(storeFileName),
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: Schema(FeedbackSchema.all),
            configurations: configuration
        )
        return FeedbackDraftStore(container: container)
    }

    public static func resetLiveStore(fileManager: FileManager = .default) throws {
        try resetStore(at: feedbackDirectoryURL(fileManager: fileManager), fileManager: fileManager)
        NotificationCenter.default.post(name: didResetNotification, object: nil)
    }

    public static func resetStore(
        at directoryURL: URL,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    public static func inMemory() throws -> FeedbackDraftStore {
        let configuration = ModelConfiguration(
            schema: Schema(FeedbackSchema.all),
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: Schema(FeedbackSchema.all),
            configurations: configuration
        )
        return FeedbackDraftStore(container: container)
    }

    @discardableResult
    public func createDraft(
        category: FeedbackCategory,
        source: FeedbackDraftSource,
        diagnostics: FeedbackDiagnostics
    ) throws -> FeedbackDraft {
        let draft = FeedbackDraft(
            category: category,
            source: source,
            diagnostics: diagnostics
        )
        context.insert(draft)
        try context.save()
        return draft
    }

    public func save(_ draft: FeedbackDraft) throws {
        draft.modifiedAt = Date()
        try context.save()
    }

    public func deleteDraft(_ draft: FeedbackDraft) throws {
        context.delete(draft)
        try context.save()
    }

    public func archive(_ draft: FeedbackDraft) throws {
        draft.archivedAt = Date()
        draft.deletedAt = nil
        try save(draft)
    }

    public func unarchive(_ draft: FeedbackDraft) throws {
        draft.archivedAt = nil
        try save(draft)
    }

    public func softDelete(_ draft: FeedbackDraft) throws {
        draft.deletedAt = Date()
        draft.archivedAt = nil
        try save(draft)
    }

    public func restore(_ draft: FeedbackDraft) throws {
        draft.deletedAt = nil
        try save(draft)
    }

    public func fetchDrafts() throws -> [FeedbackDraft] {
        var descriptor = FetchDescriptor<FeedbackDraft>(
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor)
    }

    public func fetchActiveFeedback() throws -> [FeedbackDraft] {
        try fetchDrafts()
            .filter { $0.archivedAt == nil && $0.deletedAt == nil }
            .sorted(by: feedbackSort)
    }

    public func fetchArchivedFeedback() throws -> [FeedbackDraft] {
        try fetchDrafts()
            .filter { $0.archivedAt != nil && $0.deletedAt == nil }
            .sorted {
                ($0.archivedAt ?? $0.modifiedAt) > ($1.archivedAt ?? $1.modifiedAt)
            }
    }

    public func fetchRecentlyDeletedFeedback() throws -> [FeedbackDraft] {
        try fetchDrafts()
            .filter { $0.deletedAt != nil }
            .sorted {
                ($0.deletedAt ?? $0.modifiedAt) > ($1.deletedAt ?? $1.modifiedAt)
            }
    }

    public func fetchDraft(id: UUID) throws -> FeedbackDraft? {
        var descriptor = FetchDescriptor<FeedbackDraft>(
            predicate: #Predicate { draft in
                draft.id == id
            }
        )
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor).first
    }

    public func fetchLatestRestorableDraft() throws -> FeedbackDraft? {
        let draftState = FeedbackSubmissionState.draft.rawValue
        let failedState = FeedbackSubmissionState.failed.rawValue
        var descriptor = FetchDescriptor<FeedbackDraft>(
            predicate: #Predicate { draft in
                draft.submissionStateRaw == draftState || draft.submissionStateRaw == failedState
            },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor)
            .first { $0.archivedAt == nil && $0.deletedAt == nil }
    }

    public func fetchSubmittedFeedback() throws -> [FeedbackDraft] {
        let submittedState = FeedbackSubmissionState.submitted.rawValue
        var descriptor = FetchDescriptor<FeedbackDraft>(
            predicate: #Predicate { draft in
                draft.submissionStateRaw == submittedState
            },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor)
            .filter { $0.archivedAt == nil && $0.deletedAt == nil }
            .sorted { lhs, rhs in
                (lhs.submittedAt ?? lhs.modifiedAt) > (rhs.submittedAt ?? rhs.modifiedAt)
            }
    }

    public func markSubmitted(_ draft: FeedbackDraft, issueURL: URL?) throws {
        draft.submissionState = .submitted
        draft.githubIssueURL = issueURL
        draft.submittedAt = Date()
        draft.failureMessage = nil
        try save(draft)
    }

    public func markFailed(_ draft: FeedbackDraft, message: String) throws {
        draft.submissionState = .failed
        draft.failureMessage = message
        try save(draft)
    }

    private static func ensureFeedbackDirectory(fileManager: FileManager) throws -> URL {
        let directoryURL = feedbackDirectoryURL(fileManager: fileManager)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private static func feedbackDirectoryURL(fileManager: FileManager) -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    private func feedbackSort(_ lhs: FeedbackDraft, _ rhs: FeedbackDraft) -> Bool {
        (lhs.submittedAt ?? lhs.modifiedAt) > (rhs.submittedAt ?? rhs.modifiedAt)
    }
}
