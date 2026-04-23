import SwiftUI
import PodcastSwiftCore

public struct MainView: View {
    @State private var viewModel: MainViewModel
    @State private var discoveryViewModel: DiscoveryViewModel
    @State private var selectedFeedID: FeedSubscription.ID?
    @State private var editorDraft = FeedDraft()
    @State private var isShowingFeedEditor = false
    @State private var isShowingSettings = false

    public init(viewModel: MainViewModel) {
        self._viewModel = State(initialValue: viewModel)
        self._discoveryViewModel = State(initialValue: DiscoveryViewModel())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            discoverySection

            if viewModel.hasFeeds {
                feedList
            } else {
                ContentUnavailableView(
                    "No Podcasts Yet",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Add an RSS feed to start building your sync list.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let lastErrorMessage = viewModel.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let discoveryErrorMessage = discoveryViewModel.errorMessage {
                Text(discoveryErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 460)
        .task {
            if !viewModel.hasLoadedConfiguration {
                viewModel.load()
            }
        }
        .sheet(isPresented: $isShowingFeedEditor) {
            FeedEditorView(
                title: editorDraft.id == nil ? "Add Feed" : "Edit Feed",
                draft: editorDraft
            ) { updatedDraft in
                if updatedDraft.id == nil {
                    viewModel.addFeed(from: updatedDraft)
                } else {
                    viewModel.updateFeed(from: updatedDraft)
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: viewModel.settings) { updatedSettings in
                viewModel.replaceSettings(updatedSettings)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("PodcastSwift")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Discover podcasts, manage subscriptions, and get the app ready for sync.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Settings") {
                isShowingSettings = true
            }

            Button("Add Feed") {
                editorDraft = FeedDraft()
                isShowingFeedEditor = true
            }
            .keyboardShortcut("n")
        }
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search podcasts", text: $discoveryViewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        runDiscoverySearch()
                    }

                Button(discoveryViewModel.isSearching ? "Searching..." : "Search") {
                    runDiscoverySearch()
                }
                .disabled(discoveryViewModel.isSearching)
            }

            if discoveryViewModel.hasResults {
                DiscoveryResultsList(results: discoveryResults) { result in
                    viewModel.addFeed(from: result)
                }
                .frame(minHeight: 180, maxHeight: 220)
            } else {
                Text("Search Podcast Index to add podcasts without pasting a feed URL. Manual RSS entry still works if discovery is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var feedList: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(selection: $selectedFeedID) {
                ForEach(viewModel.feedSubscriptions) { subscription in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(subscription.title)
                                .font(.headline)
                            if !subscription.isEnabled {
                                Text("Disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(subscription.rssURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Keep latest \(subscription.retentionPolicy.episodeLimit) episode\(subscription.retentionPolicy.episodeLimit == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(subscription.id)
                }
                .onDelete(perform: viewModel.removeFeeds)
            }

            HStack {
                Button("Edit Selected") {
                    guard let selectedSubscription else { return }
                    editorDraft = FeedDraft(subscription: selectedSubscription)
                    isShowingFeedEditor = true
                }
                .disabled(selectedSubscription == nil)

                Button("Remove Selected") {
                    guard let selectedFeedID else { return }
                    guard let selectedIndex = viewModel.feedSubscriptions.firstIndex(where: { $0.id == selectedFeedID }) else { return }
                    viewModel.removeFeeds(at: IndexSet(integer: selectedIndex))
                    self.selectedFeedID = nil
                }
                .disabled(selectedSubscription == nil)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Dry-run default: \(viewModel.settings.dryRunByDefault ? "On" : "Off")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Eject after sync: \(viewModel.settings.ejectAfterSyncByDefault ? "On" : "Off")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var selectedSubscription: FeedSubscription? {
        guard let selectedFeedID else { return nil }
        return viewModel.feedSubscriptions.first(where: { $0.id == selectedFeedID })
    }

    private var discoveryResults: [DiscoveryResult] {
        discoveryViewModel.results
    }

    private func runDiscoverySearch() {
        Task {
            await discoveryViewModel.search(using: viewModel.settings)
        }
    }
}

private struct DiscoveryResultsList: View {
    let results: [DiscoveryResult]
    let onSubscribe: (DiscoveryResult) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                SwiftUI.ForEach<[DiscoveryResult], String, DiscoveryResultRow>(results, id: \.id) { result in
                    DiscoveryResultRow(result: result, onSubscribe: onSubscribe)
                }
            }
        }
    }
}

private struct DiscoveryResultRow: View {
    let result: DiscoveryResult
    let onSubscribe: (DiscoveryResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.title)
                    .font(.headline)
                if let author = result.author, !author.isEmpty {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Subscribe") {
                    onSubscribe(result)
                }
                .disabled(!result.isSubscribable)
            }

            if let summary = result.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Text(result.feedURL?.absoluteString ?? "No RSS feed URL available")
                .font(.caption2)
                .foregroundStyle(result.isSubscribable ? Color.secondary : Color.orange)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
