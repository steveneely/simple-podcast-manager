import AppKit
import SwiftUI
import SpodcastManaagerCore

public struct MainView: View {
    @State private var viewModel: MainViewModel
    @State private var deviceViewModel: DeviceViewModel
    @State private var deviceLibraryViewModel: DeviceLibraryViewModel
    @State private var feedPreviewViewModel: FeedPreviewViewModel
    @State private var preparationPreviewViewModel: PreparationPreviewViewModel
    @State private var syncPlanViewModel: SyncPlanViewModel
    @State private var syncExecutionViewModel: SyncExecutionViewModel
    @State private var selectedFeedID: FeedSubscription.ID?
    @State private var editorDraft = FeedDraft()
    @State private var isShowingFeedEditor = false
    @State private var isShowingSettings = false

    public init(viewModel: MainViewModel) {
        self._viewModel = State(initialValue: viewModel)
        self._deviceViewModel = State(initialValue: DeviceViewModel())
        self._deviceLibraryViewModel = State(initialValue: DeviceLibraryViewModel())
        self._feedPreviewViewModel = State(initialValue: FeedPreviewViewModel())
        self._preparationPreviewViewModel = State(initialValue: PreparationPreviewViewModel())
        self._syncPlanViewModel = State(initialValue: SyncPlanViewModel())
        self._syncExecutionViewModel = State(initialValue: SyncExecutionViewModel())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            deviceSection

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

            if let deviceLibraryErrorMessage = deviceLibraryViewModel.lastErrorMessage {
                Text(deviceLibraryErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let syncExecutionErrorMessage = syncExecutionViewModel.lastErrorMessage {
                Text(syncExecutionErrorMessage)
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
            refreshDeviceLibrary()
            rebuildSyncPlan()
        }
        .sheet(isPresented: $isShowingFeedEditor) {
            FeedEditorView(
                title: editorDraft.id == nil ? "Add Feed" : "Edit Feed",
                draft: editorDraft
            ) { updatedDraft in
                try await saveFeed(updatedDraft)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: viewModel.settings) { updatedSettings in
                viewModel.replaceSettings(updatedSettings)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .spodcastManaagerOpenSettings)) { _ in
            isShowingSettings = true
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            handleDeviceTopologyChange()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            handleDeviceTopologyChange()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            handleDeviceTopologyChange()
        }
    }

    private var header: some View {
        HStack {
            Text("Spodcast Manaager")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()
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

                if deviceViewModel.selectedDevice != nil {
                    HoverIconButton(
                        systemName: "eject",
                        helpText: deviceViewModel.isDisconnecting ? "Disconnecting device" : "Disconnect device",
                        isDisabled: deviceViewModel.isDisconnecting
                    ) {
                        deviceViewModel.disconnectSelectedDevice()
                        refreshDeviceLibrary()
                        rebuildSyncPlan()
                    }
                }

                Button("Refresh Devices") {
                    deviceViewModel.refresh()
                    refreshDeviceLibrary()
                    rebuildSyncPlan()
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

            if let lastResult = syncExecutionViewModel.lastResult {
                Text(syncResultSummary(lastResult))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                HoverIconButton(
                    systemName: "plus",
                    helpText: "Add show"
                ) {
                    editorDraft = FeedDraft()
                    isShowingFeedEditor = true
                }
                .keyboardShortcut("n")

                HoverIconButton(
                    systemName: "arrow.clockwise",
                    helpText: feedPreviewViewModel.isLoading ? "Refreshing shows" : "Refresh shows",
                    isDisabled: feedPreviewViewModel.isLoading
                ) {
                    Task { await refreshFeedPreview() }
                }
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

                        Spacer(minLength: 8)

                        if selectedFeedID == subscription.id {
                            HStack(spacing: 8) {
                                HoverIconButton(
                                    systemName: "pencil",
                                    helpText: "Edit show"
                                ) {
                                    editorDraft = FeedDraft(subscription: subscription)
                                    isShowingFeedEditor = true
                                }

                                HoverIconButton(
                                    systemName: "trash",
                                    helpText: "Remove show",
                                    isDestructive: true
                                ) {
                                    guard let selectedIndex = viewModel.feedSubscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
                                    deleteFeeds(at: IndexSet(integer: selectedIndex))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(subscription.id)
                }
                .onDelete(perform: deleteFeeds)
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

                    HStack(spacing: 10) {
                        Button(preparationPreviewViewModel.isPreparing ? "Downloading..." : "Download All") {
                            Task {
                                await preparationPreviewViewModel.prepare(episodes(for: selectedSubscription), settings: viewModel.settings)
                                rebuildSyncPlan()
                            }
                        }
                        .disabled(preparationPreviewViewModel.isPreparing || episodes(for: selectedSubscription).isEmpty)

                        Button(syncButtonTitle) {
                            Task {
                                await syncExecutionViewModel.sync(
                                    device: deviceViewModel.selectedDevice,
                                    preparedEpisodes: preparationPreviewViewModel.preparedEpisodes,
                                    subscriptions: viewModel.feedSubscriptions,
                                    ejectAfterSync: viewModel.settings.ejectAfterSyncByDefault,
                                    isDryRun: viewModel.settings.dryRunByDefault
                                )
                                refreshDeviceLibrary()
                                rebuildSyncPlan()
                                if viewModel.hasFeeds {
                                    await refreshFeedPreview()
                                }
                                if viewModel.settings.ejectAfterSyncByDefault {
                                    deviceViewModel.refresh()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSync)
                    }
                }

                if viewModel.settings.dryRunByDefault {
                    dryRunBanner
                }

                if !preparedEpisodes(for: selectedSubscription).isEmpty {
                    syncSummaryCard(for: selectedSubscription)
                }

                if deviceViewModel.selectedDevice != nil {
                    deviceFilesSection(for: selectedSubscription)
                }

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
                if plan.isDryRun {
                    Text("Preview only. No device files will be changed.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
                HoverIconButton(
                    systemName: "trash",
                    helpText: "Remove downloaded media",
                    isDestructive: true
                ) {
                    preparationPreviewViewModel.removePreparedEpisode(for: episode)
                    rebuildSyncPlan()
                }
            } else {
                HoverIconButton(
                    systemName: "arrow.down.circle",
                    helpText: "Download episode"
                ) {
                    Task {
                        await preparationPreviewViewModel.prepare([episode], settings: viewModel.settings)
                        rebuildSyncPlan()
                    }
                }
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

    private var deviceSelectionBinding: Binding<String> {
        Binding(
            get: { deviceViewModel.selectedDevice?.id ?? "" },
            set: { newValue in
                guard !newValue.isEmpty else { return }
                deviceViewModel.selectDevice(id: newValue)
                refreshDeviceLibrary()
                rebuildSyncPlan()
            }
        )
    }

    @MainActor
    private func saveFeed(_ updatedDraft: FeedDraft) async throws {
        if updatedDraft.id == nil {
            try await viewModel.addFeed(from: updatedDraft)
        } else {
            try await viewModel.updateFeed(from: updatedDraft)
        }
        await refreshFeedPreview()
        if selectedFeedID == nil {
            selectedFeedID = viewModel.feedSubscriptions.first?.id
        }
        rebuildSyncPlan()
    }

    private func refreshFeedPreview() async {
        await feedPreviewViewModel.refreshPreview(for: viewModel.feedSubscriptions)
        viewModel.applyFeedSummaries(Array(feedPreviewViewModel.feedSummaries.values))
        refreshDeviceLibrary()
        rebuildSyncPlan()
    }

    private func rebuildSyncPlan() {
        syncPlanViewModel.buildPlan(
            device: deviceViewModel.selectedDevice,
            preparedEpisodes: preparationPreviewViewModel.preparedEpisodes,
            subscriptions: viewModel.feedSubscriptions,
            ejectAfterSync: viewModel.settings.ejectAfterSyncByDefault,
            isDryRun: viewModel.settings.dryRunByDefault
        )
    }

    private func refreshDeviceLibrary() {
        deviceLibraryViewModel.refresh(
            device: deviceViewModel.selectedDevice,
            subscriptions: viewModel.feedSubscriptions
        )
    }

    private func handleDeviceTopologyChange() {
        deviceViewModel.refresh()
        refreshDeviceLibrary()
        rebuildSyncPlan()
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

    private var canSync: Bool {
        guard !syncExecutionViewModel.isSyncing else { return false }
        guard deviceViewModel.selectedDevice != nil else { return false }
        guard let plan = syncPlanViewModel.plan else { return false }
        return plan.actions.contains(where: {
            switch $0 {
            case .copyToDevice, .deleteFromDevice, .clearDeviceTrash, .ejectDevice:
                return true
            case .skip:
                return false
            }
        })
    }

    @ViewBuilder
    private func deviceFilesSection(for subscription: FeedSubscription) -> some View {
        let deviceFiles = deviceLibraryViewModel.files(for: subscription)
        let deletions = plannedDeletionTargets(for: subscription)

        VStack(alignment: .leading, spacing: 8) {
            Text("On Device")
                .font(.headline)

            if deviceFiles.isEmpty {
                Text("No files for this show are currently on the device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(viewModel.settings.dryRunByDefault
                    ? "Checked files would be deleted in a real sync."
                    : "Checked files will be deleted on the next sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(deviceFiles, id: \.path) { fileURL in
                    HStack(spacing: 10) {
                        Image(systemName: deletions.contains(fileURL.standardizedFileURL) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(deletions.contains(fileURL.standardizedFileURL) ? Color.red : Color.secondary)
                        Text(fileURL.lastPathComponent)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func plannedDeletionTargets(for subscription: FeedSubscription) -> Set<URL> {
        guard let plan = syncPlanViewModel.plan else { return [] }
        return Set(
            plan.actions.compactMap { action in
                guard case .deleteFromDevice(let targetURL) = action else { return nil }
                let expectedDirectory = deviceViewModel.selectedDevice?.musicURL
                    .appendingPathComponent(subscription.title, isDirectory: true)
                    .standardizedFileURL
                guard targetURL.deletingLastPathComponent().standardizedFileURL == expectedDirectory else { return nil }
                return targetURL.standardizedFileURL
            }
        )
    }

    private func syncResultSummary(_ result: SyncResult) -> String {
        let finishedText = result.finishedAt?.formatted(date: .omitted, time: .shortened) ?? "now"
        if result.isDryRun {
            return "Last dry run at \(finishedText): \(result.copiedCount) would copy, \(result.deletedCount) would delete, \(result.skippedCount) would skip."
        }
        return "Last sync at \(finishedText): \(result.copiedCount) copied, \(result.deletedCount) deleted, \(result.skippedCount) skipped."
    }

    private var syncButtonTitle: String {
        if syncExecutionViewModel.isSyncing {
            return viewModel.settings.dryRunByDefault ? "Previewing..." : "Syncing..."
        }
        return viewModel.settings.dryRunByDefault ? "Preview Sync" : "Sync"
    }

    private var dryRunBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dry Run Mode")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Sync will preview copies and deletions without changing files on the device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
