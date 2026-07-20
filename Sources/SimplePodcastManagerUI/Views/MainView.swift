import AppKit
import SwiftUI
import SimplePodcastManagerCore

public struct MainView: View {
    @State private var viewModel: MainViewModel
    @State private var deviceViewModel: DeviceViewModel
    @State private var deviceLibraryViewModel: DeviceLibraryViewModel
    @State private var feedPreviewViewModel: FeedPreviewViewModel
    @State private var preparationPreviewViewModel: PreparationPreviewViewModel
    @State private var removedEpisodeHistoryViewModel: RemovedEpisodeHistoryViewModel
    @State private var syncPlanViewModel: SyncPlanViewModel
    @State private var syncExecutionViewModel: SyncExecutionViewModel
    private let devicePodcastConfigurationService = DevicePodcastConfigurationService()
    private let automaticallyChecksForUpdates: Binding<Bool>?
    private let appearancePreference: Binding<AppearancePreference>?
    @State private var selectedFeedID: FeedSubscription.ID?
    @State private var editorDraft = FeedDraft()
    @State private var feedEditorPresentationID = UUID()
    @State private var isShowingFeedEditor = false
    @State private var isShowingSettings = false
    @State private var isShowingSyncDialog = false
    @State private var isEjectAfterSyncEnabled = true
    @State private var isDeleteDownloadedAfterSyncEnabled = true
    @State private var isShowingDeviceDetails = false
    @State private var visibleEpisodeCountsByFeedID: [UUID: Int] = [:]
    @State private var expandedEpisodeIDs: Set<String> = []
    @State private var expandedDescriptionFeedIDs: Set<UUID> = []
    @State private var isHoveringDeviceStatus = false
    @State private var manuallySelectedDeletionTargets: Set<URL> = []
    @State private var selectedOtherAudioDeletionTargets: Set<URL> = []
    @State private var isShowingOtherAudioDeletionConfirmation = false
    @State private var appDataMessage: String?

    public init(
        viewModel: MainViewModel,
        automaticallyChecksForUpdates: Binding<Bool>? = nil,
        appearancePreference: Binding<AppearancePreference>? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self._deviceViewModel = State(initialValue: DeviceViewModel())
        self._deviceLibraryViewModel = State(initialValue: DeviceLibraryViewModel())
        self._feedPreviewViewModel = State(initialValue: FeedPreviewViewModel())
        self._preparationPreviewViewModel = State(initialValue: PreparationPreviewViewModel())
        self._removedEpisodeHistoryViewModel = State(initialValue: RemovedEpisodeHistoryViewModel())
        self._syncPlanViewModel = State(initialValue: SyncPlanViewModel())
        self._syncExecutionViewModel = State(initialValue: SyncExecutionViewModel())
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.appearancePreference = appearancePreference
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            deviceSection

            if viewModel.hasFeeds {
                librarySection
            } else {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "No Podcasts Yet",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Add an RSS feed to start building your sync list.")
                    )

                    Button("Add Podcast", systemImage: "plus") {
                        editorDraft = FeedDraft()
                        feedEditorPresentationID = UUID()
                        isShowingFeedEditor = true
                    }
                }
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

            if let appDataMessage {
                Text(appDataMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 460)
        .task {
            if !viewModel.hasLoadedConfiguration {
                viewModel.load()
                appearancePreference?.wrappedValue = viewModel.settings.appearancePreference
            }
            if !preparationPreviewViewModel.hasLoadedPreparedEpisodes {
                preparationPreviewViewModel.loadPersistedPreparedEpisodes()
            }
            if !removedEpisodeHistoryViewModel.hasLoadedRemovedEpisodes {
                removedEpisodeHistoryViewModel.load()
            }
            if selectedFeedID == nil {
                selectedFeedID = viewModel.feedSubscriptions.first?.id
            }
            if !deviceViewModel.hasLoadedDevices {
                deviceViewModel.refresh()
            }
            if viewModel.hasFeeds && !feedPreviewViewModel.hasPreviewData {
                await refreshFeedPreview()
            }
            await refreshDeviceLibrary()
        }
        .sheet(isPresented: $isShowingFeedEditor) {
            FeedEditorView(
                title: editorDraft.id == nil ? "Add Feed" : "Edit Feed",
                draft: editorDraft
            ) { updatedDraft in
                try await saveFeed(updatedDraft)
            }
            .id(feedEditorPresentationID)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                settings: viewModel.settings,
                selectedDeviceName: deviceViewModel.selectedDevice?.name,
                selectedDeviceRootURL: deviceViewModel.selectedDevice?.rootURL,
                podcastDirectoryPath: selectedDevicePodcastDirectoryPath,
                automaticallyChecksForUpdates: automaticallyChecksForUpdates?.wrappedValue,
                shouldConfirmPodcastDirectoryCreation: { updatedPodcastDirectoryPath in
                    try shouldConfirmPodcastDirectoryCreation(updatedPodcastDirectoryPath)
                },
                onSave: { updatedSettings, updatedPodcastDirectoryPath in
                    try saveSettings(updatedSettings, podcastDirectoryPath: updatedPodcastDirectoryPath)
                },
                onAppearancePreferencePreview: { preference in
                    appearancePreference?.wrappedValue = preference
                },
                onAutomaticallyChecksForUpdatesChange: { isEnabled in
                    automaticallyChecksForUpdates?.wrappedValue = isEnabled
                }
            )
        }
        .sheet(isPresented: $isShowingSyncDialog) {
            syncDialog
        }
        .onReceive(NotificationCenter.default.publisher(for: .simplePodcastManagerOpenSettings)) { _ in
            isShowingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .simplePodcastManagerExportAppData)) { _ in
            exportAppData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .simplePodcastManagerImportAppData)) { _ in
            importAppData()
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
        .alert("Delete Selected Other Audio?", isPresented: $isShowingOtherAudioDeletionConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Files", role: .destructive) {
                deleteSelectedOtherAudio()
            }
        } message: {
            Text(otherAudioDeletionConfirmationMessage)
        }
    }

    private var header: some View {
        HStack {
            Text("Simple Podcast Manager")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()
        }
    }

    private var deviceSection: some View {
        DeviceSectionView(
            viewModel: deviceViewModel,
            isShowingDetails: $isShowingDeviceDetails,
            isHoveringStatus: $isHoveringDeviceStatus,
            deviceSelection: deviceSelectionBinding,
            onDisconnect: {
                deviceViewModel.disconnectSelectedDevice()
                Task { await refreshDeviceLibrary() }
            },
            onRefresh: {
                deviceViewModel.refresh()
                Task { await refreshDeviceLibrary() }
            },
            syncControls: {
                Group {
                    if viewModel.hasFeeds {
                        syncControlsRow
                    }
                }
            },
            otherAudio: { otherAudioSection }
        )
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
        FeedSidebarView(
            subscriptions: viewModel.feedSubscriptions,
            selectedFeedID: $selectedFeedID,
            isRefreshing: feedPreviewViewModel.isLoading,
            episodeCount: { allEpisodes(for: $0).count },
            artworkURL: { artworkURL(for: $0) },
            onAdd: {
                editorDraft = FeedDraft()
                feedEditorPresentationID = UUID()
                isShowingFeedEditor = true
            },
            onRefresh: { Task { await refreshAllContent() } },
            onEdit: { subscription in
                editorDraft = FeedDraft(subscription: subscription)
                feedEditorPresentationID = UUID()
                isShowingFeedEditor = true
            },
            onDelete: { subscription in
                guard let index = viewModel.feedSubscriptions.firstIndex(where: { $0.id == subscription.id }) else {
                    return
                }
                deleteFeeds(at: IndexSet(integer: index))
            },
            onDeleteOffsets: deleteFeeds
        )
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

                            podcastDescriptionSection(for: selectedSubscription)
                        }
                    }

                    Spacer()

                    HoverIconButton(
                        systemName: "arrow.clockwise",
                        helpText: feedPreviewViewModel.isLoading ? "Refreshing" : "Refresh",
                        isDisabled: feedPreviewViewModel.isLoading
                    ) {
                        Task { await refreshContent(for: selectedSubscription) }
                    }
                }

                if deviceViewModel.selectedDevice != nil {
                    deviceFilesSection(for: selectedSubscription)
                }

                if preparationPreviewViewModel.isPreparing {
                    downloadsSection
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

                if allEpisodes(for: selectedSubscription).isEmpty {
                    ContentUnavailableView(
                        "No Episodes Yet",
                        systemImage: "waveform",
                        description: Text("Refresh feeds to load the latest retained episodes for this show.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(displayedEpisodes(for: selectedSubscription)) { episode in
                            episodeRow(for: episode)
                        }

                        if shouldOfferEpisodeFooter(for: selectedSubscription) {
                            episodeListFooter(for: selectedSubscription)
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
    private var syncControlsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Whole Library Sync")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(syncPlanSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Sync") {
                    openSyncDialog()
                }
                .disabled(!canOpenSyncDialog)
            }

            if let progress = syncExecutionViewModel.progress, syncExecutionViewModel.isSyncing {
                SyncProgressView(progress: progress)
            }

            if let lastResult = syncExecutionViewModel.lastResult {
                Text(SyncPresentation.resultSummary(lastResult))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var otherAudioSection: some View {
        if deviceViewModel.selectedDevice != nil, !deviceLibraryViewModel.otherAudioFiles.isEmpty {
            OtherAudioSectionView(
                files: deviceLibraryViewModel.otherAudioFiles,
                selectedFiles: selectedOtherAudioDeletionTargets,
                relativePath: relativeDevicePodcastPath,
                onToggleSelection: toggleOtherAudioDeletionSelection,
                onDeleteSelected: { isShowingOtherAudioDeletionConfirmation = true }
            )
        }
    }

    @ViewBuilder
    private var syncDialog: some View {
        SyncDialogView(
            plan: syncPlanViewModel.plan,
            progress: syncExecutionViewModel.progress,
            isSyncing: syncExecutionViewModel.isSyncing,
            isPlanning: syncPlanViewModel.isPlanning,
            planningErrorMessage: syncPlanViewModel.lastErrorMessage,
            lastResult: syncExecutionViewModel.lastResult,
            lastErrorMessage: syncExecutionViewModel.lastErrorMessage,
            preparedEpisodeCount: preparationPreviewViewModel.preparedEpisodes.count,
            enabledSubscriptionCount: enabledSubscriptionCount,
            summaryText: syncPlanSummaryText,
            isPresented: $isShowingSyncDialog,
            ejectAfterSync: $isEjectAfterSyncEnabled,
            deleteDownloadsAfterSync: $isDeleteDownloadedAfterSyncEnabled,
            onEjectAfterSyncChange: rebuildSyncPlan,
            onSync: { Task { await runSync() } }
        )
    }

    @ViewBuilder
    private func episodeRow(for episode: Episode) -> some View {
        let preparedEpisode = preparationPreviewViewModel.preparedEpisode(for: episode)
        let downloadedRecord = preparationPreviewViewModel.downloadedRecord(for: episode)
        let removedRecord = removedEpisodeHistoryViewModel.removedRecord(for: episode)

        EpisodeRowView(
            episode: episode,
            isExpanded: isEpisodeExpanded(episode),
            durationLabel: episodeDurationLabel(for: episode),
            downloadLabel: preparedEpisode.map(downloadedEpisodeLabel(for:))
                ?? downloadedRecord.map(downloadedEpisodeLabel(for:)),
            downloadWarnings: preparedEpisode?.preparationWarnings ?? [],
            removedLabel: removedRecord.map(removedEpisodeLabel(for:)),
            isPrepared: preparedEpisode != nil,
            isPreparing: preparationPreviewViewModel.isPreparing(episode),
            onToggleDetails: { toggleEpisodeDetails(for: episode) },
            onRemoveDownload: {
                preparationPreviewViewModel.removePreparedEpisode(for: episode)
                rebuildSyncPlan()
            },
            onDownload: {
                Task {
                    await preparationPreviewViewModel.prepare([episode], settings: viewModel.settings)
                    rebuildSyncPlan()
                }
            },
            details: { episodeDetails(for: episode) }
        )
    }

    @ViewBuilder
    private func episodeDetails(for episode: Episode) -> some View {
        let preparedEpisode = preparationPreviewViewModel.preparedEpisode(for: episode)
        let downloadedRecord = preparationPreviewViewModel.downloadedRecord(for: episode)
        let removedRecord = removedEpisodeHistoryViewModel.removedRecord(for: episode)
        let downloadLabel = preparedEpisode.map(downloadedEpisodeLabel(for:))
            ?? downloadedRecord.map(downloadedEpisodeLabel(for:))

        EpisodeDetailsView(
            episode: episode,
            durationLabel: episodeDurationLabel(for: episode),
            downloadLabel: downloadLabel,
            downloadWarnings: preparedEpisode?.preparationWarnings ?? [],
            removedLabel: removedRecord.map(removedEpisodeLabel(for:))
        )
    }

    private func episodeListFooter(for subscription: FeedSubscription) -> some View {
        let visibleCount = displayedEpisodes(for: subscription).count
        let totalCount = allEpisodes(for: subscription).count
        let isShowingAll = visibleCount >= totalCount

        return Button {
            if isShowingAll {
                showRecentEpisodes(for: subscription)
            } else {
                showMoreEpisodes(for: subscription)
            }
        } label: {
            HStack(spacing: 8) {
                Spacer()

                Image(systemName: isShowingAll ? "chevron.up.circle" : "chevron.down.circle")
                    .font(.body)

                Text(isShowingAll ? "Show recent only" : "\(visibleCount) of \(totalCount) episodes shown · Show more")
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }

    private var selectedSubscription: FeedSubscription? {
        if let selectedFeedID {
            return viewModel.feedSubscriptions.first(where: { $0.id == selectedFeedID })
        }
        return viewModel.feedSubscriptions.first
    }

    @ViewBuilder
    private var downloadsSection: some View {
        DownloadsSectionView(
            downloads: preparationPreviewViewModel.activeDownloads,
            progress: preparationPreviewViewModel.progress
        )
    }

    private var deviceSelectionBinding: Binding<String> {
        Binding(
            get: { deviceViewModel.selectedDevice?.id ?? "" },
            set: { newValue in
                guard !newValue.isEmpty else { return }
                deviceViewModel.selectDevice(id: newValue)
                Task { await refreshDeviceLibrary() }
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
        feedPreviewViewModel.loadCachedPreview(for: viewModel.feedSubscriptions)
        await refreshDeviceLibrary()

        if selectedFeedID == nil {
            selectedFeedID = viewModel.feedSubscriptions.first?.id
        }
    }

    private func refreshFeedPreview() async {
        await feedPreviewViewModel.refreshPreview(for: viewModel.feedSubscriptions)
        viewModel.applyFeedSummaries(Array(feedPreviewViewModel.feedSummaries.values))
    }

    private func refreshFeedPreview(for subscription: FeedSubscription) async {
        await feedPreviewViewModel.refreshPreview(for: subscription)
        viewModel.applyFeedSummaries(Array(feedPreviewViewModel.feedSummaries.values))
    }

    private func refreshAllContent() async {
        await refreshFeedPreview()
        await refreshDeviceLibrary()
    }

    private func refreshContent(for subscription: FeedSubscription) async {
        await refreshFeedPreview(for: subscription)
        await refreshDeviceLibrary()
    }

    private func rebuildSyncPlan() {
        syncPlanViewModel.prepareForPlanRebuild()
        Task {
            await syncPlanViewModel.buildPlan(
                device: deviceViewModel.selectedDevice,
                preparedEpisodes: preparationPreviewViewModel.preparedEpisodes,
                subscriptions: viewModel.feedSubscriptions,
                manualDeleteTargets: manuallySelectedDeletionTargets,
                ejectAfterSync: isEjectAfterSyncEnabled
            )
        }
    }

    private func refreshDeviceLibrary() async {
        await deviceLibraryViewModel.refresh(
            device: deviceViewModel.selectedDevice,
            subscriptions: viewModel.feedSubscriptions
        )
        pruneManualDeletionTargets()
        pruneOtherAudioDeletionTargets()
        rebuildSyncPlan()
    }

    private func handleDeviceTopologyChange() {
        deviceViewModel.refresh()
        Task { await refreshDeviceLibrary() }
    }

    private func exportAppData() {
        let panel = NSSavePanel()
        panel.title = "Export App Data"
        panel.nameFieldStringValue = AppDataBackupService.defaultBackupFileName()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let backupURL = try AppDataBackupService().exportBackup(to: destinationURL)
            appDataMessage = "Exported app data to \(backupURL.lastPathComponent)."
        } catch {
            appDataMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func importAppData() {
        let panel = NSOpenPanel()
        panel.title = "Import App Data"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let backupURL = panel.url else { return }

        do {
            let previousBackupURL = try AppDataBackupService().importBackup(from: backupURL)
            reloadAppData()
            if let previousBackupURL {
                appDataMessage = "Imported app data. Previous data was backed up to \(previousBackupURL.lastPathComponent)."
            } else {
                appDataMessage = "Imported app data."
            }
        } catch {
            appDataMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func reloadAppData() {
        viewModel.load()
        preparationPreviewViewModel.loadPersistedPreparedEpisodes()
        removedEpisodeHistoryViewModel.load()
        selectedFeedID = viewModel.feedSubscriptions.first?.id
        manuallySelectedDeletionTargets = []
        selectedOtherAudioDeletionTargets = []
        visibleEpisodeCountsByFeedID = [:]
        expandedEpisodeIDs = []
        expandedDescriptionFeedIDs = []
        Task { await refreshAllContent() }
    }

    private func deleteFeeds(at offsets: IndexSet) {
        viewModel.removeFeeds(at: offsets)
        if let selectedFeedID, !viewModel.feedSubscriptions.contains(where: { $0.id == selectedFeedID }) {
            self.selectedFeedID = viewModel.feedSubscriptions.first?.id
        }
        Task { await refreshAllContent() }
    }

    private func allEpisodes(for subscription: FeedSubscription) -> [Episode] {
        feedPreviewViewModel.allEpisodes
            .filter { $0.subscriptionID == subscription.id }
            .sorted(by: EpisodeSelector.isHigherPriority(_:than:))
    }

    private func displayedEpisodes(for subscription: FeedSubscription) -> [Episode] {
        let episodes = allEpisodes(for: subscription)
        return Array(episodes.prefix(visibleEpisodeCount(for: subscription)))
    }

    private func visibleEpisodeCount(for subscription: FeedSubscription) -> Int {
        min(visibleEpisodeCountsByFeedID[subscription.id] ?? 8, allEpisodes(for: subscription).count)
    }

    private func shouldOfferEpisodeFooter(for subscription: FeedSubscription) -> Bool {
        allEpisodes(for: subscription).count > 8
    }

    private func showMoreEpisodes(for subscription: FeedSubscription) {
        let totalCount = allEpisodes(for: subscription).count
        let nextCount = min(visibleEpisodeCount(for: subscription) + 8, totalCount)
        visibleEpisodeCountsByFeedID[subscription.id] = nextCount
    }

    private func showRecentEpisodes(for subscription: FeedSubscription) {
        visibleEpisodeCountsByFeedID[subscription.id] = nil
    }

    private func isEpisodeExpanded(_ episode: Episode) -> Bool {
        expandedEpisodeIDs.contains(episodeExpansionID(for: episode))
    }

    private func toggleEpisodeDetails(for episode: Episode) {
        let expansionID = episodeExpansionID(for: episode)
        if expandedEpisodeIDs.contains(expansionID) {
            expandedEpisodeIDs.remove(expansionID)
        } else {
            expandedEpisodeIDs.insert(expansionID)
        }
    }

    private func episodeExpansionID(for episode: Episode) -> String {
        let subscriptionID = episode.subscriptionID?.uuidString ?? episode.sourceFeedURL.absoluteString
        return "\(subscriptionID)::\(episode.id)"
    }

    @ViewBuilder
    private func podcastDescriptionSection(for subscription: FeedSubscription) -> some View {
        if let description = podcastDescription(for: subscription) {
            let isExpanded = isPodcastDescriptionExpanded(for: subscription)
            let displayedDescription = isExpanded ? description : collapsedPodcastDescription(description)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayedDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if displayedDescription != description || isExpanded {
                    Button(isExpanded ? "Show less" : "Show more") {
                        togglePodcastDescriptionExpansion(for: subscription)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }
            .padding(.top, 4)
        }
    }

    private func podcastDescription(for subscription: FeedSubscription) -> String? {
        [subscription.description, feedPreviewViewModel.description(for: subscription.id)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func isPodcastDescriptionExpanded(for subscription: FeedSubscription) -> Bool {
        expandedDescriptionFeedIDs.contains(subscription.id)
    }

    private func collapsedPodcastDescription(_ description: String) -> String {
        let maxCollapsedLength = 360
        guard description.count > maxCollapsedLength else {
            return description
        }

        let cutoffIndex = description.index(description.startIndex, offsetBy: maxCollapsedLength)
        let prefix = description[..<cutoffIndex]
        let wordBoundary = prefix.lastIndex(where: { $0 == " " || $0 == "\n" }) ?? cutoffIndex
        let trimmedPrefix = description[..<wordBoundary].trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmedPrefix)..."
    }

    private func togglePodcastDescriptionExpansion(for subscription: FeedSubscription) {
        if expandedDescriptionFeedIDs.contains(subscription.id) {
            expandedDescriptionFeedIDs.remove(subscription.id)
        } else {
            expandedDescriptionFeedIDs.insert(subscription.id)
        }
    }

    private func feedIssues(for subscription: FeedSubscription) -> [FeedFetchFailure] {
        feedPreviewViewModel.failures.filter { $0.subscriptionID == subscription.id }
    }

    private func artworkURL(for subscription: FeedSubscription) -> URL? {
        subscription.artworkURL ?? feedPreviewViewModel.artworkURL(for: subscription.id)
    }

    private var canOpenSyncDialog: Bool {
        deviceViewModel.selectedDevice != nil && !viewModel.feedSubscriptions.isEmpty
    }

    private var enabledSubscriptionCount: Int {
        viewModel.feedSubscriptions.filter(\.isEnabled).count
    }

    private var syncPlanSummaryText: String {
        guard let plan = syncPlanViewModel.plan else {
            if syncPlanViewModel.isPlanning {
                return "Checking the sync plan and available device space..."
            }
            if syncPlanViewModel.lastErrorMessage != nil {
                return "The sync plan could not be completed."
            }
            return deviceViewModel.selectedDevice == nil
                ? "Pick a compatible device to build the plan."
                : "The plan will appear here once episodes are prepared."
        }

        let actionCount = plan.actions.count
        return "Review the full-device plan for all shows. \(actionCount) action\(actionCount == 1 ? "" : "s") planned."
    }

    private func runSync() async {
        let filesBySubscriptionID = Dictionary(uniqueKeysWithValues: viewModel.feedSubscriptions.map {
            ($0.id, deviceLibraryViewModel.files(for: $0))
        })
        let episodesBySubscriptionID = Dictionary(grouping: feedPreviewViewModel.allEpisodes.compactMap { episode -> (UUID, Episode)? in
            guard let subscriptionID = episode.subscriptionID else { return nil }
            return (subscriptionID, episode)
        }, by: \.0).mapValues { $0.map(\.1) }

        await syncExecutionViewModel.sync(plan: syncPlanViewModel.plan)

        if
            let result = syncExecutionViewModel.lastResult,
            let lastPlan = syncExecutionViewModel.lastPlan
        {
            let deletedTargetURLs = lastPlan.actions.compactMap { action -> URL? in
                guard case .deleteFromDevice(let targetURL, _) = action else { return nil }
                return targetURL
            }
            removedEpisodeHistoryViewModel.recordDeletedEpisodes(
                deletedTargetURLs: deletedTargetURLs,
                filesBySubscriptionID: filesBySubscriptionID,
                episodesBySubscriptionID: episodesBySubscriptionID,
                deviceName: deviceViewModel.selectedDevice?.name,
                removedAt: result.finishedAt ?? Date()
            )
        }

        if
            isDeleteDownloadedAfterSyncEnabled,
            syncExecutionViewModel.lastErrorMessage == nil,
            syncExecutionViewModel.lastResult != nil
        {
            preparationPreviewViewModel.removeAllPreparedEpisodes()
        }

        if isEjectAfterSyncEnabled {
            deviceViewModel.refresh()
        }
        await refreshDeviceLibrary()
    }

    private func openSyncDialog() {
        syncExecutionViewModel.clearLastResult()
        isEjectAfterSyncEnabled = true
        isDeleteDownloadedAfterSyncEnabled = true
        rebuildSyncPlan()
        isShowingSyncDialog = true
    }

    private func removedEpisodeLabel(for record: RemovedEpisodeRecord) -> String {
        let removedDate = record.removedAt.formatted(date: .abbreviated, time: .omitted)
        return "Removed from MP3 player \(removedDate)"
    }

    private func episodeDurationLabel(for episode: Episode) -> String? {
        if let duration = episode.duration, duration > 0 {
            return formatEpisodeDuration(duration)
        }
        return nil
    }

    private func formatEpisodeDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(1, Int((duration / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func downloadedEpisodeLabel(for preparedEpisode: PreparedEpisode) -> String {
        let actionText = preparedEpisode.preparationAction == .passthroughMP3 ? "MP3" : "converted to MP3"
        let downloadedDate = preparedEpisode.preparedAt.formatted(date: .abbreviated, time: .omitted)
        return "Downloaded \(downloadedDate) (\(actionText))"
    }

    private func downloadedEpisodeLabel(for record: DownloadedEpisodeRecord) -> String {
        let actionText = record.preparationAction == .passthroughMP3 ? "MP3" : "converted to MP3"
        let downloadedDate = record.downloadedAt.formatted(date: .abbreviated, time: .omitted)
        return "Downloaded \(downloadedDate) (\(actionText))"
    }

    private func toggleDeletionSelection(for fileURL: URL) {
        let fileURL = fileURL.standardizedFileURL
        if manuallySelectedDeletionTargets.contains(fileURL) {
            manuallySelectedDeletionTargets.remove(fileURL)
        } else {
            manuallySelectedDeletionTargets.insert(fileURL)
        }
        rebuildSyncPlan()
    }

    private func toggleOtherAudioDeletionSelection(for fileURL: URL) {
        let fileURL = fileURL.standardizedFileURL
        if selectedOtherAudioDeletionTargets.contains(fileURL) {
            selectedOtherAudioDeletionTargets.remove(fileURL)
        } else {
            selectedOtherAudioDeletionTargets.insert(fileURL)
        }
    }

    private func deleteSelectedOtherAudio() {
        deviceLibraryViewModel.deleteOtherAudioFiles(
            selectedOtherAudioDeletionTargets,
            on: deviceViewModel.selectedDevice
        )
        selectedOtherAudioDeletionTargets = []
        Task { await refreshDeviceLibrary() }
    }

    private func pruneManualDeletionTargets() {
        let allKnownFiles = Set(
            viewModel.feedSubscriptions
                .flatMap { deviceLibraryViewModel.files(for: $0) }
                .map(\.standardizedFileURL)
        )
        manuallySelectedDeletionTargets = manuallySelectedDeletionTargets.intersection(allKnownFiles)
    }

    private func pruneOtherAudioDeletionTargets() {
        let allOtherAudioFiles = Set(deviceLibraryViewModel.otherAudioFiles.map(\.standardizedFileURL))
        selectedOtherAudioDeletionTargets = selectedOtherAudioDeletionTargets.intersection(allOtherAudioFiles)
    }

    @ViewBuilder
    private func deviceFilesSection(for subscription: FeedSubscription) -> some View {
        let deviceFiles = deviceLibraryViewModel.files(for: subscription)
        let deletions = selectedDeletionTargets(for: subscription)

        VStack(alignment: .leading, spacing: 8) {
            Text("On Device")
                .font(.headline)

            if deviceFiles.isEmpty {
                Text("No files for this show are currently on the device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Checked files stay on the device. Uncheck a file to delete it on the next run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(deviceFiles, id: \.path) { fileURL in
                    Button {
                        toggleDeletionSelection(for: fileURL)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: deletions.contains(fileURL.standardizedFileURL) ? "square" : "checkmark.square.fill")
                                .foregroundStyle(deletions.contains(fileURL.standardizedFileURL) ? Color.red : Color.accentColor)
                            Text(fileURL.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func selectedDeletionTargets(for subscription: FeedSubscription) -> Set<URL> {
        let deviceFiles = Set(deviceLibraryViewModel.files(for: subscription).map(\.standardizedFileURL))
        return manuallySelectedDeletionTargets.intersection(deviceFiles)
    }

    private var otherAudioDeletionConfirmationMessage: String {
        let count = selectedOtherAudioDeletionTargets.count
        return "Delete \(count) selected file\(count == 1 ? "" : "s") from the MP3 player? These files are not associated with a podcast subscription in Simple Podcast Manager. They will be deleted directly from the MP3 player. This cannot be undone."
    }

    private var selectedDevicePodcastDirectoryPath: String? {
        guard let selectedDevice = deviceViewModel.selectedDevice else { return nil }
        return devicePodcastConfigurationService.relativePodcastDirectoryPath(on: selectedDevice)
    }

    private func saveSettings(_ updatedSettings: AppSettings, podcastDirectoryPath: String?) throws {
        if let podcastDirectoryPath,
           let selectedDevice = deviceViewModel.selectedDevice {
            _ = try devicePodcastConfigurationService.savePodcastDirectoryPath(podcastDirectoryPath, on: selectedDevice)
        }

        viewModel.replaceSettings(updatedSettings)
        appearancePreference?.wrappedValue = updatedSettings.appearancePreference

        if podcastDirectoryPath != nil {
            deviceViewModel.refresh()
            Task { await refreshDeviceLibrary() }
        }
    }

    private func shouldConfirmPodcastDirectoryCreation(_ podcastDirectoryPath: String?) throws -> Bool {
        guard let podcastDirectoryPath,
              let selectedDevice = deviceViewModel.selectedDevice else {
            return false
        }

        return try !devicePodcastConfigurationService.podcastDirectoryExists(podcastDirectoryPath, on: selectedDevice)
    }

    private func relativeDevicePodcastPath(for fileURL: URL) -> String {
        guard let podcastDirectoryURL = deviceViewModel.selectedDevice?.podcastDirectoryURL.standardizedFileURL else {
            return fileURL.lastPathComponent
        }

        let filePath = fileURL.standardizedFileURL.path
        let podcastDirectoryPath = podcastDirectoryURL.path
        guard filePath.hasPrefix(podcastDirectoryPath) else {
            return fileURL.lastPathComponent
        }

        return String(filePath.dropFirst(podcastDirectoryPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

}
