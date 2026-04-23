import SwiftUI
import PodcastSwiftCore

public struct MainView: View {
    @State private var viewModel: MainViewModel
    @State private var discoveryViewModel: DiscoveryViewModel
    @State private var deviceViewModel: DeviceViewModel
    @State private var feedPreviewViewModel: FeedPreviewViewModel
    @State private var preparationPreviewViewModel: PreparationPreviewViewModel
    @State private var syncPlanViewModel: SyncPlanViewModel
    @State private var selectedFeedID: FeedSubscription.ID?
    @State private var editorDraft = FeedDraft()
    @State private var isShowingFeedEditor = false
    @State private var isShowingSettings = false
    @FocusState private var searchFieldFocused: Bool

    public init(viewModel: MainViewModel) {
        self._viewModel = State(initialValue: viewModel)
        self._discoveryViewModel = State(initialValue: DiscoveryViewModel())
        self._deviceViewModel = State(initialValue: DeviceViewModel())
        self._feedPreviewViewModel = State(initialValue: FeedPreviewViewModel())
        self._preparationPreviewViewModel = State(initialValue: PreparationPreviewViewModel())
        self._syncPlanViewModel = State(initialValue: SyncPlanViewModel())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            deviceSection
            discoverySection

            if viewModel.hasFeeds {
                librarySection
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

            if let feedPreviewErrorMessage = feedPreviewViewModel.lastErrorMessage {
                Text(feedPreviewErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let preparationErrorMessage = preparationPreviewViewModel.lastErrorMessage {
                Text(preparationErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let syncPlanErrorMessage = syncPlanViewModel.lastErrorMessage {
                Text(syncPlanErrorMessage)
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
            if !deviceViewModel.hasLoadedDevices {
                deviceViewModel.refresh()
            }
            if viewModel.hasFeeds && !feedPreviewViewModel.hasPreviewData {
                await refreshFeedPreview()
            }
            if !preparationPreviewViewModel.hasLoadedPreparedEpisodes {
                preparationPreviewViewModel.loadPersistedPreparedEpisodes()
            }
            if selectedFeedID == nil {
                selectedFeedID = viewModel.feedSubscriptions.first?.id
            }
            rebuildSyncPlan()
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
                Task {
                    await refreshFeedPreview()
                    if selectedFeedID == nil {
                        selectedFeedID = viewModel.feedSubscriptions.first?.id
                    }
                    rebuildSyncPlan()
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
                Text("Podcast Swift")
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
                    .focused($searchFieldFocused)
                    .inputFieldStyle(isFocused: searchFieldFocused)
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

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device")
                        .font(.headline)
                    Text(deviceViewModel.statusMessage)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Refresh Devices") {
                    deviceViewModel.refresh()
                }
            }

            if deviceViewModel.hasMultipleDevices {
                Picker("Target device", selection: deviceSelectionBinding) {
                    Text("Choose a device")
                        .tag("")
                    ForEach(deviceViewModel.devices) { device in
                        Text(device.name)
                            .tag(device.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if let selectedDevice = deviceViewModel.selectedDevice {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mounted at: \(selectedDevice.rootURL.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Music folder: \(selectedDevice.musicURL.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Trash folder: \(selectedDevice.trashURL.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let deviceErrorMessage = deviceViewModel.lastErrorMessage {
                Text(deviceErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var librarySection: some View {
        HSplitView {
            feedSidebar
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
            episodeDetailSection
                .frame(minWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var feedSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shows")
                    .font(.headline)
                Spacer()
                Button(feedPreviewViewModel.isLoading ? "Refreshing..." : "Refresh") {
                    Task { await refreshFeedPreview() }
                }
                .disabled(feedPreviewViewModel.isLoading)
            }

            List(selection: $selectedFeedID) {
                ForEach(viewModel.feedSubscriptions) { subscription in
                    HStack(alignment: .top, spacing: 10) {
                        PodcastArtworkView(
                            artworkURL: artworkURL(for: subscription),
                            size: 42,
                            cornerRadius: 9
                        )

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

                            Text("\(episodes(for: subscription).count) episode\(episodes(for: subscription).count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(subscription.id)
                }
                .onDelete(perform: deleteFeeds)
            }

            HStack {
                Button("Edit") {
                    guard let selectedSubscription else { return }
                    editorDraft = FeedDraft(subscription: selectedSubscription)
                    isShowingFeedEditor = true
                }
                .disabled(selectedSubscription == nil)

                Button("Remove") {
                    guard let selectedFeedID else { return }
                    guard let selectedIndex = viewModel.feedSubscriptions.firstIndex(where: { $0.id == selectedFeedID }) else { return }
                    deleteFeeds(at: IndexSet(integer: selectedIndex))
                }
                .disabled(selectedSubscription == nil)
            }
        }
        .padding(14)
    }

    private var episodeDetailSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedSubscription {
                HStack(alignment: .top) {
                    HStack(alignment: .top, spacing: 12) {
                        PodcastArtworkView(
                            artworkURL: artworkURL(for: selectedSubscription),
                            size: 72,
                            cornerRadius: 16
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedSubscription.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text(selectedSubscription.rssURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(preparationPreviewViewModel.isPreparing ? "Downloading..." : "Download All") {
                        Task {
                            await preparationPreviewViewModel.prepare(episodes(for: selectedSubscription), settings: viewModel.settings)
                            rebuildSyncPlan()
                        }
                    }
                    .disabled(preparationPreviewViewModel.isPreparing || episodes(for: selectedSubscription).isEmpty)
                }

                syncSummaryCard(for: selectedSubscription)

                if let progress = preparationPreviewViewModel.progress {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(progress.currentEpisodeTitle.map { "Downloading \($0)" } ?? "Finishing downloads")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        ProgressView(value: progress.fractionCompleted)
                            .progressViewStyle(.linear)
                        Text("\(progress.completedCount) of \(progress.totalCount) complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !feedIssues(for: selectedSubscription).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Feed Issues")
                            .font(.headline)
                        ForEach(feedIssues(for: selectedSubscription)) { failure in
                            Text(failure.message)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if episodes(for: selectedSubscription).isEmpty {
                    ContentUnavailableView(
                        "No Episodes Yet",
                        systemImage: "waveform",
                        description: Text("Refresh feeds to load the latest retained episodes for this show.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(episodes(for: selectedSubscription)) { episode in
                            episodeRow(for: episode)
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                ContentUnavailableView(
                    "Choose a Show",
                    systemImage: "music.note.list",
                    description: Text("Select a feed to browse its current episodes.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private func syncSummaryCard(for subscription: FeedSubscription) -> some View {
        let plan = syncPlanViewModel.plan
        let relevantPreparedCount = preparedEpisodes(for: subscription).count

        VStack(alignment: .leading, spacing: 8) {
            Text("Sync Summary")
                .font(.headline)

            if let plan {
                let copyCount = plan.actions.filter {
                    if case .copyToDevice = $0 { return true }
                    return false
                }.count
                let deleteCount = plan.actions.filter {
                    if case .deleteFromDevice = $0 { return true }
                    return false
                }.count
                let skipCount = plan.actions.filter {
                    if case .skip = $0 { return true }
                    return false
                }.count

                Text("\(relevantPreparedCount) ready, \(copyCount) to copy, \(skipCount) to skip, \(deleteCount) to delete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(relevantPreparedCount == 0 ? "Download episodes to build a sync plan." : "\(relevantPreparedCount) ready to sync. Sync plan will be rebuilt automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func episodeRow(for episode: Episode) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.body)
                    .fontWeight(.medium)
                if let publicationDate = episode.publicationDate {
                    Text(publicationDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let preparedEpisode = preparationPreviewViewModel.preparedEpisode(for: episode) {
                    Text(preparedEpisode.preparationAction == .passthroughMP3 ? "Downloaded MP3" : "Downloaded and converted to MP3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if preparationPreviewViewModel.preparedEpisode(for: episode) != nil {
                Button {
                    preparationPreviewViewModel.removePreparedEpisode(for: episode)
                    rebuildSyncPlan()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove downloaded media")
            } else {
                Button {
                    Task {
                        await preparationPreviewViewModel.prepare([episode], settings: viewModel.settings)
                        rebuildSyncPlan()
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .help("Download episode")
            }
        }
        .padding(.vertical, 4)
    }

    private var selectedSubscription: FeedSubscription? {
        if let selectedFeedID {
            return viewModel.feedSubscriptions.first(where: { $0.id == selectedFeedID })
        }
        return viewModel.feedSubscriptions.first
    }

    private var discoveryResults: [DiscoveryResult] {
        discoveryViewModel.results
    }

    private var deviceSelectionBinding: Binding<String> {
        Binding(
            get: { deviceViewModel.selectedDevice?.id ?? "" },
            set: { newValue in
                guard !newValue.isEmpty else { return }
                deviceViewModel.selectDevice(id: newValue)
            }
        )
    }

    private func runDiscoverySearch() {
        Task {
            await discoveryViewModel.search(using: viewModel.settings)
        }
    }

    private func refreshFeedPreview() async {
        await feedPreviewViewModel.refreshPreview(for: viewModel.feedSubscriptions)
        rebuildSyncPlan()
    }

    private func rebuildSyncPlan() {
        syncPlanViewModel.buildPlan(
            device: deviceViewModel.selectedDevice,
            preparedEpisodes: preparationPreviewViewModel.preparedEpisodes,
            subscriptions: viewModel.feedSubscriptions,
            ejectAfterSync: viewModel.settings.ejectAfterSyncByDefault,
            isDryRun: true
        )
    }

    private func deleteFeeds(at offsets: IndexSet) {
        viewModel.removeFeeds(at: offsets)
        if let selectedFeedID, !viewModel.feedSubscriptions.contains(where: { $0.id == selectedFeedID }) {
            self.selectedFeedID = viewModel.feedSubscriptions.first?.id
        }
        Task { await refreshFeedPreview() }
    }

    private func episodes(for subscription: FeedSubscription) -> [Episode] {
        feedPreviewViewModel.selectedEpisodes
            .filter { $0.subscriptionID == subscription.id }
            .sorted(by: EpisodeSelector.isHigherPriority(_:than:))
    }

    private func preparedEpisodes(for subscription: FeedSubscription) -> [PreparedEpisode] {
        preparationPreviewViewModel.preparedEpisodes
            .filter { $0.episode.subscriptionID == subscription.id }
    }

    private func feedIssues(for subscription: FeedSubscription) -> [FeedFetchFailure] {
        feedPreviewViewModel.failures.filter { $0.subscriptionID == subscription.id }
    }

    private func artworkURL(for subscription: FeedSubscription) -> URL? {
        subscription.artworkURL ?? feedPreviewViewModel.artworkURL(for: subscription.id)
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
        HStack(alignment: .top, spacing: 12) {
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 56,
                cornerRadius: 12
            )

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
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
