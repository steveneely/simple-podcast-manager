import SimplePodcastManagerCore
import SwiftUI

public struct FeedEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: FeedDraft
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var addMethod: AddMethod
    @State private var selectedSearchResult: PodcastSearchResult?
    @FocusState private var focusedField: Field?
    private let title: String
    private let initialDraft: FeedDraft
    private let podcastSearcher: any PodcastSearching
    private let existingSubscriptions: [FeedSubscription]
    private let onSave: @Sendable (FeedDraft) async throws -> Void

    private enum Field: Hashable {
        case rssURL
    }

    private enum AddMethod: String, CaseIterable, Identifiable {
        case search
        case feedURL

        var id: Self { self }
    }

    public init(
        title: String,
        draft: FeedDraft,
        podcastSearcher: any PodcastSearching = PodcastIndexSearchService(),
        existingSubscriptions: [FeedSubscription] = [],
        onSave: @escaping @Sendable (FeedDraft) async throws -> Void
    ) {
        self.title = title
        self.initialDraft = draft
        self._draft = State(initialValue: draft)
        self._addMethod = State(initialValue: draft.id == nil ? .search : .feedURL)
        self.podcastSearcher = podcastSearcher
        self.existingSubscriptions = existingSubscriptions
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(dialogTitle)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 14) {
                if isCreatingFeed {
                    Picker("Add podcast using", selection: $addMethod) {
                        Text("Search").tag(AddMethod.search)
                        Text("Feed URL").tag(AddMethod.feedURL)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if addMethod == .search {
                        PodcastSearchView(
                            searcher: podcastSearcher,
                            existingSubscriptions: existingSubscriptions,
                            selectedResult: $selectedSearchResult
                        )
                    } else {
                        feedURLAddView
                    }
                } else {
                    feedURLField
                }

                Toggle("Feed enabled", isOn: $draft.isEnabled)

                Toggle("Include in automatic downloads", isOn: $draft.includesInAutomaticDownloads)
                    .disabled(!draft.isEnabled)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(primaryButtonTitle) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSave || isSaving)
            }
        }
        .padding(20)
        .frame(
            minWidth: isCreatingFeed ? 560 : 460,
            minHeight: isCreatingFeed ? 520 : nil
        )
        .onAppear {
            draft = initialDraft
            focusedField = nil
        }
        .onChange(of: addMethod) { _, addMethod in
            errorMessage = nil
            selectedSearchResult = nil
            draft.rssURLString = ""
            if addMethod == .feedURL {
                focusedField = .rssURL
            }
        }
        .onChange(of: selectedSearchResult) { _, selectedSearchResult in
            draft.rssURLString = selectedSearchResult?.feedURL.absoluteString ?? ""
            errorMessage = nil
        }
    }

    private var feedURLField: some View {
        LabeledField(
            title: "Feed URL",
            detail: "Paste the podcast's RSS feed address."
        ) {
            TextField("https://example.com/feed.xml", text: $draft.rssURLString)
                .focused($focusedField, equals: .rssURL)
                .inputFieldStyle(isFocused: focusedField == .rssURL)
        }
    }

    private var feedURLAddView: some View {
        VStack(alignment: .leading, spacing: 10) {
            feedURLField

            ContentUnavailableView(
                "Add with a Feed URL",
                systemImage: "link",
                description: Text(
                    "Use the podcast's RSS feed when it is private or missing from search."
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: 250)

            Text("The app reads podcast details and episodes directly from this feed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var primaryButtonTitle: String {
        if isSaving {
            return isCreatingFeed ? "Adding..." : "Saving..."
        }
        return isCreatingFeed ? "Add Podcast" : "Save"
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }

            do {
                try await onSave(draft)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private var isCreatingFeed: Bool {
        draft.id == nil
    }

    private var dialogTitle: String {
        if let currentTitle = draft.currentTitle, !currentTitle.isEmpty {
            return currentTitle
        }
        return title
    }
}
