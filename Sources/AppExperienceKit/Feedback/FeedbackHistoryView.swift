import SwiftUI
import UniformTypeIdentifiers

public struct FeedbackHistoryView: View {
    @Environment(\.feedbackPaneOpener) private var feedbackPaneOpener
    @Environment(\.openWindow) private var openWindow

    @State private var store: FeedbackDraftStore?
    @State private var activeDrafts: [FeedbackDraft] = []
    @State private var archivedDrafts: [FeedbackDraft] = []
    @State private var deletedDrafts: [FeedbackDraft] = []
    @State private var isLoading = false
    @State private var isExportingAll = false
    @State private var exportError: String?
    @State private var sheetSelection: FeedbackDraftSheetSelection?
    @State private var archivedExpanded = false
    @State private var deletedExpanded = false

    private let renderer = FeedbackExportRenderer()

    public init() { }

    public var body: some View {
        Group {
            if isLoading && allDrafts.isEmpty {
                ProgressView("Loading feedback...")
            } else if allDrafts.isEmpty {
                ContentUnavailableView(
                    "No Feedback",
                    systemImage: FeedbackVisualIdentity.systemImage,
                    description: Text("Feedback drafts and submissions stay on this device until you explicitly share or export them.")
                )
            } else {
                feedbackList
            }
        }
        .navigationTitle("My Feedback")
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                if !exportableDrafts.isEmpty {
                    ShareLink(
                        item: renderer.markdown(for: exportableDrafts),
                        preview: SharePreview("My Feedback")
                    ) {
                        Label("Share Feedback", systemImage: "square.and.arrow.up")
                    }

                    Button("Export All", systemImage: "doc") {
                        isExportingAll = true
                    }
                    .accessibilityLabel("Export All feedback")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Add Feedback", systemImage: "plus") {
                    addFeedback()
                }
                .accessibilityLabel("Add feedback")
            }
        }
        .fileExporter(
            isPresented: $isExportingAll,
            document: FeedbackMarkdownDocument(text: renderer.markdown(for: exportableDrafts)),
            contentType: .plainText,
            defaultFilename: "my-feedback.md"
        ) { result in
            if case let .failure(error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert("Feedback Error", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(role: .cancel) { exportError = nil } label: {
                Text("OK")
            }
        } message: {
            Text(exportError ?? "The feedback action could not be completed.")
        }
        .sheet(item: $sheetSelection, onDismiss: {
            Task { await loadFeedback() }
        }) { selection in
            NavigationStack {
                FeedbackView(
                    launchContext: selection.launchContext,
                    showsPopOutButton: false,
                    onSubmitted: { sheetSelection = nil }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            sheetSelection = nil
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible) // Adds the grabber handle
        .task {
            await loadFeedback()
        }
        .onReceive(NotificationCenter.default.publisher(for: FeedbackDraftStore.didResetNotification)) { _ in
            store = nil
            activeDrafts = []
            archivedDrafts = []
            deletedDrafts = []
            exportError = nil
        }
    }

    private var feedbackList: some View {
        List {
            if !activeDrafts.isEmpty {
                Section {
                    ForEach(activeDrafts, id: \.id) { draft in
                        editableRow(draft)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    Task { await mutate { try $0.archive(draft) } }
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }

                                Button(role: .destructive) {
                                    Task { await mutate { try $0.softDelete(draft) } }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } footer: {
                    Text("Feedback is stored locally on this device. Use Share or Export when you want to send it elsewhere.")
                }
            }

            if !archivedDrafts.isEmpty {
                recoveryHeader(
                    title: "Archived",
                    systemImage: "archivebox",
                    isExpanded: $archivedExpanded
                )

                if archivedExpanded {
                    ForEach(archivedDrafts, id: \.id) { draft in
                        editableRow(draft)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    Task { await mutate { try $0.unarchive(draft) } }
                                } label: {
                                    Label("Unarchive", systemImage: "archivebox")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await mutate { try $0.softDelete(draft) } }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            if !deletedDrafts.isEmpty {
                recoveryHeader(
                    title: "Recently Deleted",
                    systemImage: "trash",
                    isExpanded: $deletedExpanded
                )

                if deletedExpanded {
                    Text("Feedback in Recently Deleted stays local until you restore it or delete it forever.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(deletedDrafts, id: \.id) { draft in
                        editableRow(draft)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    Task { await mutate { try $0.restore(draft) } }
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await mutate { try $0.deleteDraft(draft) } }
                                } label: {
                                    Label("Delete Forever", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await loadFeedback()
        }
    }

    private var allDrafts: [FeedbackDraft] {
        activeDrafts + archivedDrafts + deletedDrafts
    }

    private var exportableDrafts: [FeedbackDraft] {
        activeDrafts + archivedDrafts
    }

    private func editableRow(_ draft: FeedbackDraft) -> some View {
        Button {
            sheetSelection = FeedbackDraftSheetSelection(draft: draft)
        } label: {
            FeedbackHistoryRow(draft: draft)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", systemImage: "square.and.pencil") {
                sheetSelection = FeedbackDraftSheetSelection(draft: draft)
            }

            if draft.deletedAt != nil {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    Task { await mutate { try $0.restore(draft) } }
                }

                Button("Delete Forever", systemImage: "trash", role: .destructive) {
                    Task { await mutate { try $0.deleteDraft(draft) } }
                }
            } else if draft.archivedAt != nil {
                Button("Unarchive", systemImage: "archivebox") {
                    Task { await mutate { try $0.unarchive(draft) } }
                }

                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task { await mutate { try $0.softDelete(draft) } }
                }
            } else {
                Button("Archive", systemImage: "archivebox") {
                    Task { await mutate { try $0.archive(draft) } }
                }

                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task { await mutate { try $0.softDelete(draft) } }
                }
            }
        }
    }

    private func recoveryHeader(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addFeedback() {
        let launchContext = FeedbackLaunchContext(source: .feedbackNavigation)
        if AppExperiencePlatform.isPhone {
            sheetSelection = FeedbackDraftSheetSelection(launchContext: launchContext)
        } else if !feedbackPaneOpener.open(launchContext) {
            openWindow(id: FeedbackLaunchContext.windowID, value: launchContext)
        }
    }

    @MainActor
    private func loadFeedback() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let activeStore = try feedbackStore()
            activeDrafts = try activeStore.fetchActiveFeedback()
            archivedDrafts = try activeStore.fetchArchivedFeedback()
            deletedDrafts = try activeStore.fetchRecentlyDeletedFeedback()
        } catch {
            exportError = error.localizedDescription
        }
    }

    @MainActor
    private func mutate(_ action: (FeedbackDraftStore) throws -> Void) async {
        do {
            let activeStore = try feedbackStore()
            try action(activeStore)
            await loadFeedback()
        } catch {
            exportError = error.localizedDescription
        }
    }

    @MainActor
    private func feedbackStore() throws -> FeedbackDraftStore {
        if let store {
            return store
        }

        let loadedStore = try FeedbackDraftStore.live()
        store = loadedStore
        return loadedStore
    }
}

private struct FeedbackDraftSheetSelection: Identifiable {
    let id: UUID
    let launchContext: FeedbackLaunchContext

    init(draft: FeedbackDraft) {
        self.id = draft.id
        self.launchContext = FeedbackLaunchContext(source: .feedbackNavigation, draftID: draft.id)
    }

    init(launchContext: FeedbackLaunchContext) {
        self.id = UUID()
        self.launchContext = launchContext
    }
}

private struct FeedbackHistoryRow: View {
    let draft: FeedbackDraft

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FeedbackIdentityIcon(size: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(draft.category.displayName, systemImage: "tag")
                    Text(status)
                    Text(timestamp)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        FeedbackIssueRenderer().title(for: draft)
    }

    private var summary: String {
        let trimmed = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No summary provided." : trimmed
    }

    private var status: String {
        if draft.deletedAt != nil {
            return "Deleted"
        }

        if draft.archivedAt != nil {
            return "Archived"
        }

        switch draft.submissionState {
        case .draft:
            return "Draft"
        case .failed:
            return "Failed"
        case .submitted:
            return draft.githubIssueURL == nil ? "Local" : "GitHub"
        }
    }

    private var timestamp: String {
        let date = draft.deletedAt ?? draft.archivedAt ?? draft.submittedAt ?? draft.modifiedAt
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
