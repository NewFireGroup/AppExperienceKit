import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct FeedbackExportRenderer: Sendable {
    private let issueRenderer = FeedbackIssueRenderer()

    public init() { }

    public func markdown(for draft: FeedbackDraft) -> String {
        let issueURL = draft.githubIssueURL?.absoluteString
        let destination = issueURL.map { "GitHub (\($0))" } ?? "Local"
        var metadata = [
            "Submission destination: \(destination)",
            "Submission state: \(draft.submissionState.rawValue)"
        ]

        if let submittedAt = draft.submittedAt {
            metadata.append("Submitted: \(submittedAt.formatted(date: .abbreviated, time: .shortened))")
        }

        metadata.append("Category: \(draft.category.displayName)")
        metadata.append("Source: \(draft.source.displayName)")

        return """
        # \(issueRenderer.title(for: draft))

        \(metadata.joined(separator: "\n"))

        \(issueRenderer.body(for: draft))
        """
    }

    public func markdown(for drafts: [FeedbackDraft]) -> String {
        let entries = drafts
            .map { markdown(for: $0) }
            .joined(separator: "\n\n---\n\n")

        return """
        # My Feedback

        Exported: \(Date().formatted(date: .abbreviated, time: .shortened))
        Feedback count: \(drafts.count)

        \(entries)
        """
    }
}

public struct FeedbackMarkdownDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.plainText] }
    public static var writableContentTypes: [UTType] { [.plainText] }

    public var text: String

    public init(text: String = "") {
        self.text = text
    }

    public init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            self.text = text
        } else {
            self.text = ""
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
