import SimplePodcastManagerCore
import SwiftUI

struct PodcastSearchView: View {
    @State private var viewModel: PodcastSearchViewModel
    @State private var searchTask: Task<Void, Never>?
    @Binding private var selectedResult: PodcastSearchResult?
    @FocusState private var isSearchFieldFocused: Bool
    private let subscriptionMatcher: PodcastSearchSubscriptionMatcher

    init(
        searcher: any PodcastSearching,
        existingSubscriptions: [PodcastSubscription],
        selectedResult: Binding<PodcastSearchResult?>
    ) {
        self._viewModel = State(initialValue: PodcastSearchViewModel(searcher: searcher))
        self._selectedResult = selectedResult
        self.subscriptionMatcher = PodcastSearchSubscriptionMatcher(
            subscriptions: existingSubscriptions
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledField(
                title: "Find a podcast",
                detail: "Search by podcast title or creator."
            ) {
                HStack(spacing: 8) {
                    TextField("Podcast name", text: $viewModel.query)
                        .focused($isSearchFieldFocused)
                        .inputFieldStyle(isFocused: isSearchFieldFocused)
                        .onSubmit(performSearch)

                    Button {
                        performSearch()
                    } label: {
                        if viewModel.isSearching {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        } else {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(!viewModel.canSearch)
                }
            }

            searchResults

            HStack(spacing: 0) {
                Text("Searches are sent to ")
                Link(
                    "https://podcastindex.org",
                    destination: URL(string: "https://podcastindex.org")!
                )
                Text(".")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            isSearchFieldFocused = true
        }
        .onChange(of: viewModel.query) {
            searchTask?.cancel()
            searchTask = nil
            viewModel.clearResults()
            selectedResult = nil
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
            viewModel.cancelSearch()
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if let searchErrorMessage = viewModel.lastErrorMessage {
            ContentUnavailableView {
                Label("Search Unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(searchErrorMessage)
            } actions: {
                Button("Try Again") {
                    performSearch()
                }
                .disabled(!viewModel.canSearch)
            }
            .frame(maxWidth: .infinity, minHeight: 250)
        } else if viewModel.hasSearched && viewModel.results.isEmpty {
            ContentUnavailableView.search(text: viewModel.query)
                .frame(maxWidth: .infinity, minHeight: 250)
        } else if viewModel.results.isEmpty {
            ContentUnavailableView(
                "Search for a Podcast",
                systemImage: "magnifyingglass"
            )
            .frame(maxWidth: .infinity, minHeight: 250)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.results) { result in
                        searchResultRow(result)
                    }
                }
                .padding(6)
            }
            .frame(height: 250)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }

    private func searchResultRow(_ result: PodcastSearchResult) -> some View {
        let isSubscribed = subscriptionMatcher.isSubscribed(result)

        return Button {
            selectedResult = Self.selection(
                afterClicking: result,
                currentSelection: selectedResult
            )
        } label: {
            HStack(spacing: 10) {
                PodcastArtworkView(
                    artworkURL: result.artworkURL,
                    allowsInsecureHTTP: false,
                    size: 46,
                    cornerRadius: 8
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let author = result.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    if isSubscribed {
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let episodeCount = result.episodeCount {
                        Text("\(episodeCount) episodes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if result.isExplicit {
                        Text("Explicit")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isSubscribed {
                    Image(systemName: selectedResult?.id == result.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedResult?.id == result.id ? Color.accentColor : Color.secondary)
                }
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(
                selectedResult?.id == result.id
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isSubscribed)
        .accessibilityHint(
            isSubscribed
                ? "This podcast is already in your library"
                : selectedResult?.id == result.id
                    ? "Deselects this podcast"
                    : "Uses this podcast's RSS feed"
        )
    }

    static func selection(
        afterClicking result: PodcastSearchResult,
        currentSelection: PodcastSearchResult?
    ) -> PodcastSearchResult? {
        currentSelection?.id == result.id ? nil : result
    }

    private func performSearch() {
        guard viewModel.canSearch else { return }
        searchTask?.cancel()
        searchTask = Task {
            await viewModel.search()
        }
    }
}
