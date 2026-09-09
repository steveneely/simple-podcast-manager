import SimplePodcastManagerCore
import SwiftUI

public struct PodcastEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PodcastDraft
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var addMethod: AddMethod
    @State private var selectedSearchResult: PodcastSearchResult?
    @State private var searchViewModel: PodcastSearchViewModel
    @State private var rssFeedURLString: String
    @FocusState private var focusedField: Field?
    private let title: String
    private let initialDraft: PodcastDraft
    private let existingSubscriptions: [PodcastSubscription]
    private let onSave: @Sendable (PodcastDraft) async throws -> Void

    private enum Field: Hashable {
        case rssURL
    }

    enum AddMethod: String, CaseIterable, Identifiable {
        case search
        case rssFeedURL

        var id: Self { self }
    }

    public init(
        title: String,
        draft: PodcastDraft,
        podcastSearcher: any PodcastSearching = PodcastIndexSearchService(),
        existingSubscriptions: [PodcastSubscription] = [],
        onSave: @escaping @Sendable (PodcastDraft) async throws -> Void
    ) {
        self.title = title
        self.initialDraft = draft
        self._draft = State(initialValue: draft)
        self._addMethod = State(initialValue: draft.id == nil ? .search : .rssFeedURL)
        self._searchViewModel = State(
            initialValue: PodcastSearchViewModel(searcher: podcastSearcher)
        )
        self._rssFeedURLString = State(initialValue: draft.rssURLString)
        self.existingSubscriptions = existingSubscriptions
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(dialogTitle)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 14) {
                if isCreatingPodcast {
                    Picker("Add podcast using", selection: $addMethod) {
                        Text("Search").tag(AddMethod.search)
                        Text("Feed URL").tag(AddMethod.rssFeedURL)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if addMethod == .search {
                        PodcastSearchView(
                            viewModel: searchViewModel,
                            existingSubscriptions: existingSubscriptions,
                            selectedResult: $selectedSearchResult
                        )
                    } else {
                        rssFeedURLAddView
                    }
                } else {
                    rssFeedURLField
                }

                Toggle("Podcast enabled", isOn: $draft.isEnabled)

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
            minWidth: isCreatingPodcast ? 560 : 460,
            minHeight: isCreatingPodcast ? 520 : nil
        )
        .onAppear {
            draft = initialDraft
            rssFeedURLString = initialDraft.rssURLString
            focusedField = nil
        }
        .onChange(of: addMethod) { _, addMethod in
            errorMessage = nil
            draft.rssURLString = Self.activeRSSURLString(
                for: addMethod,
                selectedSearchResult: selectedSearchResult,
                rssFeedURLString: rssFeedURLString
            )
            if addMethod == .rssFeedURL {
                focusedField = .rssURL
            }
        }
        .onChange(of: selectedSearchResult) { _, selectedSearchResult in
            if addMethod == .search {
                draft.rssURLString = selectedSearchResult?.feedURL.absoluteString ?? ""
            }
            errorMessage = nil
        }
    }

    private var rssFeedURLField: some View {
        LabeledField(
            title: "RSS Feed URL",
            detail: "Paste the podcast's RSS feed address."
        ) {
            TextField("https://example.com/feed.xml", text: rssFeedURLBinding)
                .focused($focusedField, equals: .rssURL)
                .inputFieldStyle(isFocused: focusedField == .rssURL)
        }
    }

    private var rssFeedURLAddView: some View {
        VStack(alignment: .leading, spacing: 10) {
            rssFeedURLField

            ContentUnavailableView(
                "Add with an RSS Feed URL",
                systemImage: "link"
            )
            .frame(maxWidth: .infinity)
            .frame(height: 250)

            Text("The app reads podcast details and episodes directly from this feed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var rssFeedURLBinding: Binding<String> {
        Binding(
            get: { rssFeedURLString },
            set: { updatedURLString in
                rssFeedURLString = updatedURLString
                if addMethod == .rssFeedURL {
                    draft.rssURLString = updatedURLString
                }
            }
        )
    }

    static func activeRSSURLString(
        for addMethod: AddMethod,
        selectedSearchResult: PodcastSearchResult?,
        rssFeedURLString: String
    ) -> String {
        switch addMethod {
        case .search:
            selectedSearchResult?.feedURL.absoluteString ?? ""
        case .rssFeedURL:
            rssFeedURLString
        }
    }

    private var primaryButtonTitle: String {
        if isSaving {
            return isCreatingPodcast ? "Adding..." : "Saving..."
        }
        return isCreatingPodcast ? "Add Podcast" : "Save"
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

    private var isCreatingPodcast: Bool {
        draft.id == nil
    }

    private var dialogTitle: String {
        if let currentTitle = draft.currentTitle, !currentTitle.isEmpty {
            return currentTitle
        }
        return title
    }
}
