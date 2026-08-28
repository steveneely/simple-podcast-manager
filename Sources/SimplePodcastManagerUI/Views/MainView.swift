import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SimplePodcastManagerCore

struct FeedEditorPresentation: Identifiable {
    let id = UUID()
    let draft: FeedDraft

    init(draft: FeedDraft) {
        self.draft = draft
    }

    init(subscription: FeedSubscription) {
        self.draft = FeedDraft(subscription: subscription)
    }
}

public struct MainView: View {
    @State private var viewModel: MainViewModel
    @State private var deviceViewModel: DeviceViewModel
    @State private var deviceLibraryViewModel: DeviceLibraryViewModel
    @State private var feedPreviewViewModel: FeedPreviewViewModel
    @State private var preparationPreviewViewModel: PreparationPreviewViewModel
    @State private var automaticDownloadViewModel: AutomaticDownloadViewModel
    @State private var feedActivityViewModel: FeedActivityViewModel
    @State private var removedEpisodeHistoryViewModel: RemovedEpisodeHistoryViewModel
    @State private var syncPlanViewModel: SyncPlanViewModel
    @State private var syncExecutionViewModel: SyncExecutionViewModel
    private let devicePodcastConfigurationService = DevicePodcastConfigurationService()
    private let startupEpisodeStateStore: any EpisodeStateStartupLoading
    private let startupPerformanceTracker = StartupPerformanceTracker()
    private let automaticallyChecksForUpdates: Binding<Bool>?
    private let appearancePreference: Binding<AppearancePreference>?
    @State private var selectedFeedID = FeedSelectionPolicy.initialSelection
    @State private var feedEditorPresentation: FeedEditorPresentation?
    @State private var pendingFeedDeletionConfirmation: FeedDeletionConfirmation?
    @State private var isShowingSettings = false
    @State private var isShowingSyncDialog = false
    @State private var isEjectAfterSyncEnabled = true
    @State private var isDeleteDownloadedAfterSyncEnabled = true
    @State private var isShowingDeviceDetails = false
    @State private var visibleEpisodeCountsByFeedID: [UUID: Int] = [:]
    @State private var expandedEpisodeIDs: Set<String> = []
    @State private var expandedDescriptionFeedIDs: Set<UUID> = []
    @State private var manuallySelectedDeletionTargets: Set<URL> = []
    @State private var excludedCleanupDeletionTargets: Set<URL> = []
    @State private var selectedOtherAudioDeletionTargets: Set<URL> = []
    @State private var isShowingOtherAudioDeletionConfirmation = false
    @State private var appDataMessage: String?
    @State private var opmlImportPreview: OPMLSubscriptionImportPreview?
    @State private var insecureDownloadEpisode: Episode?
    @State private var insecureDownloadQueue: [Episode] = []
    @State private var temporarilyAllowedInsecureArtworkURLs: Set<URL> = []

    public init(
        viewModel: MainViewModel,
        automaticallyChecksForUpdates: Binding<Bool>? = nil,
        appearancePreference: Binding<AppearancePreference>? = nil,
        startupEpisodeStateStore: any EpisodeStateStartupLoading = SQLiteEpisodeStore.shared
    ) {
        self._viewModel = State(initialValue: viewModel)
        self._deviceViewModel = State(initialValue: DeviceViewModel())
        self._deviceLibraryViewModel = State(initialValue: DeviceLibraryViewModel())
        self._feedPreviewViewModel = State(initialValue: FeedPreviewViewModel())
        self._preparationPreviewViewModel = State(initialValue: PreparationPreviewViewModel())
        self._automaticDownloadViewModel = State(initialValue: AutomaticDownloadViewModel())
        self._feedActivityViewModel = State(initialValue: FeedActivityViewModel())
        self._removedEpisodeHistoryViewModel = State(initialValue: RemovedEpisodeHistoryViewModel())
        self._syncPlanViewModel = State(initialValue: SyncPlanViewModel())
        self._syncExecutionViewModel = State(initialValue: SyncExecutionViewModel())
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.appearancePreference = appearancePreference
        self.startupEpisodeStateStore = startupEpisodeStateStore
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                        feedEditorPresentation = FeedEditorPresentation(draft: FeedDraft())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let applicationErrorMessage {
                Text(applicationErrorMessage)
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if preparationPreviewViewModel.isPreparing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(globalDownloadStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .overlay {
            if let opmlImportPreview {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())

                    OPMLImportReviewView(
                        preview: opmlImportPreview,
                        onCancel: { self.opmlImportPreview = nil },
                        onImport: { try importOPMLSubscriptions(opmlImportPreview) }
                    )
                    .background(Color(NSColor.windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 18)
                    .padding(24)
                }
            }
        }
        .task {
            if !viewModel.hasLoadedConfiguration {
                await viewModel.load()
                appearancePreference?.wrappedValue = viewModel.settings.appearancePreference
                startupPerformanceTracker.mark("configuration loaded")
            }
            async let cachedPreview: Void = loadCachedFeedPreviewForStartup()
            async let persistedState: Void = loadPersistedEpisodeStateForStartup()
            async let devices: Void = loadDevicesForStartup()
            _ = await (cachedPreview, persistedState)

            async let refreshedFeeds: Void = refreshFeedsForStartup()
            await devices
            async let deviceLibrary: Void = refreshDeviceLibrary()
            _ = await (refreshedFeeds, deviceLibrary)
            startupPerformanceTracker.mark("background startup work complete")
        }
        .sheet(item: $feedEditorPresentation) { presentation in
            FeedEditorView(
                title: presentation.draft.id == nil ? "Add Feed" : "Edit Feed",
                draft: presentation.draft
            ) { updatedDraft in
                try await saveFeed(updatedDraft)
            }
        }
        .onChange(of: selectedFeedID) { _, selectedFeedID in
            guard let selectedFeedID else { return }
            Task { await feedActivityViewModel.markSeen(subscriptionID: selectedFeedID) }
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
                },
                onBackUpAppData: exportAppData,
                onRestoreAppData: importAppData
            )
        }
        .sheet(isPresented: $isShowingSyncDialog) {
            syncDialog
        }
        .onReceive(NotificationCenter.default.publisher(for: .simplePodcastManagerAddPodcastFeed)) { _ in
            feedEditorPresentation = FeedEditorPresentation(draft: FeedDraft())
        }
        .onReceive(NotificationCenter.default.publisher(for: .simplePodcastManagerOpenSettings)) { _ in
            isShowingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .simplePodcastManagerExportSubscriptions)) { _ in
            exportOPMLSubscriptions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .simplePodcastManagerImportSubscriptions)) { _ in
            openOPMLSubscriptionImport()
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
        .alert(
            pendingFeedDeletionConfirmation?.title ?? "Delete Podcast Feed?",
            isPresented: Binding(
                get: { pendingFeedDeletionConfirmation != nil },
                set: { if !$0 { pendingFeedDeletionConfirmation = nil } }
            ),
            presenting: pendingFeedDeletionConfirmation
        ) { confirmation in
            Button(confirmation.cancelButtonTitle, role: .cancel) {}
            Button(confirmation.deleteButtonTitle, role: .destructive) {
                confirmFeedDeletion(confirmation)
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
        .alert("Delete Selected Other Audio?", isPresented: $isShowingOtherAudioDeletionConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Files", role: .destructive) {
                deleteSelectedOtherAudio()
            }
        } message: {
            Text(otherAudioDeletionConfirmationMessage)
        }
        .alert(
            "Allow Insecure Download?",
            isPresented: Binding(
                get: { insecureDownloadEpisode != nil },
                set: { if !$0 { insecureDownloadEpisode = nil } }
            ),
            presenting: insecureDownloadEpisode
        ) { episode in
            Button("Cancel", role: .cancel) {
                finishInsecureDownloadPrompt()
            }
            Button("Download Once") {
                retryInsecureDownload(episode, alwaysAllow: false)
            }
            Button("Always Allow", role: .destructive) {
                retryInsecureDownload(episode, alwaysAllow: true)
            }
        } message: { episode in
            Text("Some files for “\(episode.title)” are only available over unencrypted HTTP. The audio or artwork could be intercepted or changed in transit. Simple Podcast Manager tried HTTPS first.")
        }
    }

    private var globalDownloadStatusText: String {
        let count = preparationPreviewViewModel.preparingEpisodeCount
        return "\(count) downloading"
    }

    private var deviceSection: some View {
        DeviceSectionView(
            viewModel: deviceViewModel,
            isShowingDetails: $isShowingDeviceDetails,
            libraryErrorMessage: deviceLibraryViewModel.lastErrorMessage,
            deviceSelection: deviceSelectionBinding,
            onDisconnect: {
                Task {
                    await deviceViewModel.disconnectSelectedDevice()
                    await refreshDeviceLibrary()
                }
            },
            onRefresh: {
                Task {
                    await deviceViewModel.refresh()
                    await refreshDeviceLibrary()
                }
            },
            syncControls: {
                if viewModel.hasFeeds, deviceViewModel.selectedDevice != nil {
                    syncControlsRow
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
            newEpisodeCount: { subscription in
                subscription.isEnabled ? feedActivityViewModel.newEpisodeCount(for: subscription.id) : 0
            },
            isInactive: { subscription in
                subscription.isEnabled
                    && viewModel.settings.inactivePodcastThreshold != .off
                    && feedActivityViewModel.isInactive(
                    subscriptionID: subscription.id,
                    threshold: viewModel.settings.inactivePodcastThreshold
                )
            },
            newestPublicationDate: { feedActivityViewModel.newestPublicationDate(for: $0.id) },
            hasFeedIssue: { !feedIssues(for: $0).isEmpty },
            artworkURL: { artworkURL(for: $0) },
            allowsInsecureArtwork: { allowsInsecureArtwork(for: $0) },
            onAdd: {
                feedEditorPresentation = FeedEditorPresentation(draft: FeedDraft())
            },
            onRefresh: { Task { await refreshAllContent() } },
            onRefreshSubscription: { subscription in
                Task { await refreshContent(for: subscription) }
            },
            onEdit: { subscription in
                feedEditorPresentation = FeedEditorPresentation(subscription: subscription)
            },
            onDelete: { subscription in
                guard let index = viewModel.feedSubscriptions.firstIndex(where: { $0.id == subscription.id }) else {
                    return
                }
                requestFeedDeletion(at: IndexSet(integer: index))
            },
            onDeleteOffsets: requestFeedDeletion
        )
    }

    private var episodeDetailSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedSubscription {
                HStack(alignment: .top, spacing: 12) {
                    PodcastArtworkView(
                        artworkURL: artworkURL(for: selectedSubscription),
                        allowsInsecureHTTP: allowsInsecureArtwork(for: selectedSubscription),
                        size: 72,
                        cornerRadius: 16
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedSubscription.title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        podcastDescriptionSection(for: selectedSubscription)
                    }

                    Spacer()
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

                if let feedPreviewErrorMessage = feedPreviewViewModel.lastErrorMessage {
                    Text(feedPreviewErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if allEpisodes(for: selectedSubscription).isEmpty,
                   unmatchedDeviceFiles(for: selectedSubscription).isEmpty {
                    if feedPreviewViewModel.isLoading {
                        VStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Loading episodes…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "No Episodes Yet",
                            systemImage: "waveform",
                            description: Text("Refresh feeds to load the latest retained episodes for this show.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    List {
                        ForEach(displayedEpisodes(for: selectedSubscription)) { episode in
                            episodeRow(for: episode)
                        }

                        olderDeviceFilesSection(for: selectedSubscription)

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
        HStack {
            if let lastResult = syncExecutionViewModel.lastResult {
                Text(SyncPresentation.resultSummary(lastResult))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Sync") {
                openSyncDialog()
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
            cleanupMaximumEpisodesPerShow: viewModel.settings.deviceCleanupPolicy.maximumEpisodesPerShow,
            isPresented: $isShowingSyncDialog,
            ejectAfterSync: $isEjectAfterSyncEnabled,
            deleteDownloadsAfterSync: $isDeleteDownloadedAfterSyncEnabled,
            onEjectAfterSyncChange: rebuildSyncPlan,
            onToggleCleanupDeletion: toggleCleanupDeletionSelection,
            onSync: { Task { await runSync() } }
        )
    }

    @ViewBuilder
    private func episodeRow(for episode: Episode) -> some View {
        let status = episodeStatus(for: episode)
        let deviceFileURL = status.deviceFileURL
        let isSelectedForDeviceRemoval = deviceFileURL.map {
            manuallySelectedDeletionTargets.contains($0.standardizedFileURL)
        } ?? false

        EpisodeRowView(
            episode: episode,
            isExpanded: isEpisodeExpanded(episode),
            durationLabel: episodeDurationLabel(for: episode),
            downloadLabel: status.preparedEpisode.map(downloadedEpisodeLabel(for:))
                ?? status.downloadedRecord.map(downloadedEpisodeLabel(for:)),
            downloadWarnings: status.preparedEpisode?.preparationWarnings ?? [],
            downloadErrorMessage: status.preparationFailure?.message,
            removedLabel: visibleRemovedLabel(for: status),
            isOnDevice: deviceFileURL != nil,
            isSelectedForDeviceRemoval: isSelectedForDeviceRemoval,
            isPrepared: status.preparedEpisode != nil,
            isPreparing: preparationPreviewViewModel.isPreparing(episode),
            onToggleDetails: { toggleEpisodeDetails(for: episode) },
            onToggleDeviceRemoval: {
                if let deviceFileURL {
                    toggleDeletionSelection(for: deviceFileURL)
                }
            },
            onRemoveDownload: {
                preparationPreviewViewModel.removePreparedEpisode(for: episode)
                rebuildSyncPlan()
            },
            onDownload: {
                Task {
                    await preparationPreviewViewModel.prepare([episode], settings: viewModel.settings)
                    if preparationPreviewViewModel.requiresInsecureDownloadPermission(for: episode) {
                        enqueueInsecureDownloadPermissions(for: [episode])
                    }
                    rebuildSyncPlan()
                }
            },
            details: { episodeDetails(for: episode, status: status) }
        )
    }

    private func retryInsecureDownload(_ episode: Episode, alwaysAllow: Bool) {
        insecureDownloadEpisode = nil
        var downloadSettings = viewModel.settings
        downloadSettings.allowsInsecureDownloads = true
        var episodesToPrepare = [episode]

        if alwaysAllow {
            viewModel.replaceSettings(downloadSettings)
            episodesToPrepare.append(contentsOf: insecureDownloadQueue)
            insecureDownloadQueue.removeAll()
        } else {
            allowArtworkOnce(for: episode)
        }
        let requestedEpisodes = episodesToPrepare
        let requestedSettings = downloadSettings

        Task {
            await preparationPreviewViewModel.prepare(requestedEpisodes, settings: requestedSettings)
            await automaticDownloadViewModel.markDownloaded(requestedEpisodes.filter {
                preparationPreviewViewModel.downloadedRecord(for: $0) != nil
            })
            rebuildSyncPlan()
            showNextInsecureDownloadPrompt()
        }
    }

    private func enqueueInsecureDownloadPermissions(for episodes: [Episode]) {
        var queuedIDs = Set(([insecureDownloadEpisode].compactMap { $0 } + insecureDownloadQueue).compactMap {
            AutomaticDownloadEpisodeID($0)
        })
        insecureDownloadQueue.append(contentsOf: episodes.filter { episode in
            guard let episodeID = AutomaticDownloadEpisodeID(episode) else { return false }
            return queuedIDs.insert(episodeID).inserted
        })
        showNextInsecureDownloadPrompt()
    }

    private func finishInsecureDownloadPrompt() {
        insecureDownloadEpisode = nil
        showNextInsecureDownloadPrompt()
    }

    private func showNextInsecureDownloadPrompt() {
        guard insecureDownloadEpisode == nil, !insecureDownloadQueue.isEmpty else { return }
        insecureDownloadEpisode = insecureDownloadQueue.removeFirst()
    }

    private func allowArtworkOnce(for episode: Episode) {
        if let artworkURL = episode.artworkURL {
            temporarilyAllowedInsecureArtworkURLs.insert(artworkURL)
        }

        guard let subscriptionID = episode.subscriptionID,
              let subscription = viewModel.feedSubscriptions.first(where: { $0.id == subscriptionID }),
              let artworkURL = artworkURL(for: subscription) else {
            return
        }
        temporarilyAllowedInsecureArtworkURLs.insert(artworkURL)
    }

    private func allowsInsecureArtwork(for subscription: FeedSubscription) -> Bool {
        guard let artworkURL = artworkURL(for: subscription) else { return false }
        return viewModel.settings.allowsInsecureDownloads
            || temporarilyAllowedInsecureArtworkURLs.contains(artworkURL)
    }

    @ViewBuilder
    private func episodeDetails(for episode: Episode, status: EpisodeStatus) -> some View {
        EpisodeDetailsView(
            episode: episode,
            durationLabel: episodeDurationLabel(for: episode),
            downloadLabel: status.preparedEpisode.map(downloadedEpisodeLabel(for:))
                ?? status.downloadedRecord.map(downloadedEpisodeLabel(for:)),
            downloadWarnings: status.preparedEpisode?.preparationWarnings ?? [],
            removedLabel: visibleRemovedLabel(for: status)
        )
    }

    private func visibleRemovedLabel(for status: EpisodeStatus) -> String? {
        guard status.deviceFileURL == nil else {
            return nil
        }
        return status.removedRecord.map(removedEpisodeLabel(for:))
    }

    private func episodeStatus(for episode: Episode) -> EpisodeStatus {
        EpisodeStatus(
            preparedEpisode: preparationPreviewViewModel.preparedEpisode(for: episode),
            downloadedRecord: preparationPreviewViewModel.downloadedRecord(for: episode),
            removedRecord: removedEpisodeHistoryViewModel.removedRecord(for: episode),
            preparationFailure: preparationPreviewViewModel.failure(for: episode),
            deviceFileURL: deviceLibraryViewModel.file(for: episode)
        )
    }

    @ViewBuilder
    private func olderDeviceFilesSection(for subscription: FeedSubscription) -> some View {
        let unmatchedFiles = unmatchedDeviceFiles(for: subscription)

        if deviceViewModel.selectedDevice != nil, !unmatchedFiles.isEmpty {
            DisclosureGroup {
                ForEach(unmatchedFiles, id: \.path) { fileURL in
                    let standardizedFileURL = fileURL.standardizedFileURL
                    let isSelectedForRemoval = manuallySelectedDeletionTargets.contains(standardizedFileURL)

                    HStack(spacing: 8) {
                        Text(EpisodeFileName.parsedMetadata(from: fileURL)?.episodeTitle ?? fileURL.lastPathComponent)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        DevicePresenceToggle(
                            isSelectedForRemoval: isSelectedForRemoval,
                            onToggleSelection: {
                                toggleDeletionSelection(for: fileURL)
                            }
                        )
                    }
                    .padding(.vertical, 3)
                }
            } label: {
                Text("Older episodes on MP3 player (\(unmatchedFiles.count))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)
        }
    }

    private func unmatchedDeviceFiles(for subscription: FeedSubscription) -> [URL] {
        deviceLibraryViewModel.unmatchedFiles(
            for: subscription,
            episodes: allEpisodes(for: subscription)
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
        guard let selectedFeedID else { return nil }
        return viewModel.feedSubscriptions.first(where: { $0.id == selectedFeedID })
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
            let subscriptionID = try viewModel.addFeed(from: updatedDraft)
            refreshAddedSubscriptions(withIDs: [subscriptionID])
            return
        }

        let previousRSSURL = updatedDraft.id.flatMap { subscriptionID in
            viewModel.feedSubscriptions.first(where: { $0.id == subscriptionID })?.rssURL
        }
        try await viewModel.updateFeed(from: updatedDraft)
        await automaticDownloadViewModel.applyPreferences(
            subscriptions: viewModel.feedSubscriptions,
            limit: viewModel.settings.automaticDownloadLimit
        )
        await feedPreviewViewModel.loadCachedPreview(for: viewModel.feedSubscriptions)
        if let subscription = viewModel.feedSubscriptions.first(where: { $0.id == updatedDraft.id }),
           previousRSSURL != subscription.rssURL {
            await feedActivityViewModel.updateAfterRefresh(
                subscriptions: viewModel.feedSubscriptions,
                episodes: feedPreviewViewModel.allEpisodes,
                refreshedSubscriptionIDs: [subscription.id],
                failedSubscriptionIDs: [],
                openSubscriptionID: selectedFeedID
            )
        }
        await refreshDeviceLibrary()
    }

    private func refreshFeedPreview() async {
        let refreshedSubscriptions = viewModel.feedSubscriptions.filter(\.isEnabled)
        await feedPreviewViewModel.refreshPreview(for: refreshedSubscriptions)
        viewModel.applyFeedSummaries(Array(feedPreviewViewModel.feedSummaries.values))
        await updateFeedActivity(afterRefreshing: refreshedSubscriptions)
        await downloadNewEpisodes(afterRefreshing: refreshedSubscriptions)
    }

    private func loadCachedFeedPreviewForStartup() async {
        guard viewModel.hasFeeds, !feedPreviewViewModel.hasPreviewData else { return }
        await feedPreviewViewModel.loadCachedPreview(for: viewModel.feedSubscriptions)
        startupPerformanceTracker.mark("cached episodes visible")
    }

    private func loadPersistedEpisodeStateForStartup(forceReload: Bool = false) async {
        guard forceReload
            || !preparationPreviewViewModel.hasLoadedPreparedEpisodes
            || !automaticDownloadViewModel.hasLoadedState
            || !feedActivityViewModel.hasLoadedState
            || !removedEpisodeHistoryViewModel.hasLoadedRemovedEpisodes
        else { return }

        do {
            let store = startupEpisodeStateStore
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try store.loadStartupSnapshot()
            }.value
            try await preparationPreviewViewModel.applyPersistedState(
                preparedEpisodes: snapshot.preparedEpisodes,
                downloadedEpisodes: snapshot.downloadedEpisodes
            )
            automaticDownloadViewModel.applyPersistedState(snapshot.automaticDownloadState)
            feedActivityViewModel.applyPersistedState(snapshot.feedActivityState)
            removedEpisodeHistoryViewModel.applyPersistedState(snapshot.removedEpisodes)
            startupPerformanceTracker.mark("persisted episode state ready")
        } catch {
            // Preserve the existing per-view-model fallback behavior if a future custom
            // startup store cannot provide a complete snapshot.
            await preparationPreviewViewModel.loadPersistedPreparedEpisodes()
            await automaticDownloadViewModel.load()
            await feedActivityViewModel.load()
            await removedEpisodeHistoryViewModel.load()
        }
    }

    private func loadDevicesForStartup() async {
        guard !deviceViewModel.hasLoadedDevices else { return }
        await deviceViewModel.refresh()
        startupPerformanceTracker.mark("devices discovered")
    }

    private func refreshFeedsForStartup() async {
        guard viewModel.hasFeeds else { return }
        await refreshFeedPreview()
        startupPerformanceTracker.mark("network feeds refreshed")
    }

    private func refreshFeedPreview(for subscription: FeedSubscription) async {
        await feedPreviewViewModel.refreshPreview(for: subscription)
        viewModel.applyFeedSummaries(Array(feedPreviewViewModel.feedSummaries.values))
        await updateFeedActivity(afterRefreshing: [subscription])
        await downloadNewEpisodes(afterRefreshing: [subscription])
    }

    private func refreshFeedPreview(forNewSubscriptions subscriptions: [FeedSubscription]) async {
        await feedPreviewViewModel.refreshPreview(forNewSubscriptions: subscriptions)
        viewModel.applyFeedSummaries(Array(feedPreviewViewModel.feedSummaries.values))
        await updateFeedActivity(afterRefreshing: subscriptions)
        await downloadNewEpisodes(afterRefreshing: subscriptions)
    }

    private func updateFeedActivity(afterRefreshing subscriptions: [FeedSubscription]) async {
        let refreshedIDs = Set(subscriptions.filter(\.isEnabled).map(\.id))
        let failedIDs: Set<UUID>
        if feedPreviewViewModel.lastErrorMessage != nil {
            failedIDs = refreshedIDs
        } else {
            failedIDs = Set(feedPreviewViewModel.failures.compactMap {
                refreshedIDs.contains($0.subscriptionID) ? $0.subscriptionID : nil
            })
        }
        await feedActivityViewModel.updateAfterRefresh(
            subscriptions: viewModel.feedSubscriptions,
            episodes: feedPreviewViewModel.allEpisodes,
            refreshedSubscriptionIDs: refreshedIDs,
            failedSubscriptionIDs: failedIDs,
            openSubscriptionID: selectedFeedID
        )
    }

    private func downloadNewEpisodes(afterRefreshing subscriptions: [FeedSubscription]) async {
        let refreshedSubscriptionIDs = Set(subscriptions.filter(\.isEnabled).map(\.id))
        let failedSubscriptionIDs: Set<UUID>
        if feedPreviewViewModel.lastErrorMessage != nil {
            failedSubscriptionIDs = refreshedSubscriptionIDs
        } else {
            failedSubscriptionIDs = Set(feedPreviewViewModel.failures.compactMap { failure in
                refreshedSubscriptionIDs.contains(failure.subscriptionID) ? failure.subscriptionID : nil
            })
        }
        let episodes = await automaticDownloadViewModel.episodesToDownload(
            afterRefreshing: refreshedSubscriptionIDs,
            failedSubscriptionIDs: failedSubscriptionIDs,
            subscriptions: viewModel.feedSubscriptions,
            episodes: feedPreviewViewModel.allEpisodes,
            downloadedEpisodeIDs: preparationPreviewViewModel.downloadedEpisodeIDs,
            limit: viewModel.settings.automaticDownloadLimit
        )
        guard !episodes.isEmpty else { return }

        await preparationPreviewViewModel.prepare(episodes, settings: viewModel.settings)
        let downloadedEpisodes = episodes.filter {
            preparationPreviewViewModel.downloadedRecord(for: $0) != nil
        }
        await automaticDownloadViewModel.markDownloaded(downloadedEpisodes)
        enqueueInsecureDownloadPermissions(for: episodes.filter {
            preparationPreviewViewModel.requiresInsecureDownloadPermission(for: $0)
        })
        rebuildSyncPlan()
    }

    private func refreshAllContent() async {
        await refreshFeedPreview()
        await refreshDeviceLibrary()
    }

    private func refreshContent(for subscription: FeedSubscription) async {
        await refreshFeedPreview(for: subscription)
        await refreshDeviceLibrary()
    }

    private func refreshAddedSubscriptions(withIDs subscriptionIDs: [FeedSubscription.ID]) {
        guard !subscriptionIDs.isEmpty else { return }
        let addedIDSet = Set(subscriptionIDs)
        let addedSubscriptions = viewModel.feedSubscriptions.filter { addedIDSet.contains($0.id) }
        guard !addedSubscriptions.isEmpty else { return }

        selectedFeedID = subscriptionIDs[0]
        Task {
            await refreshFeedPreview(forNewSubscriptions: addedSubscriptions)
            await refreshDeviceLibrary()
        }
    }

    private func rebuildSyncPlan() {
        syncPlanViewModel.prepareForPlanRebuild()
        Task {
            await syncPlanViewModel.buildPlan(
                device: deviceViewModel.selectedDevice,
                preparedEpisodes: preparationPreviewViewModel.preparedEpisodes,
                subscriptions: viewModel.feedSubscriptions,
                manualDeleteTargets: manuallySelectedDeletionTargets,
                cleanupPolicy: viewModel.settings.deviceCleanupPolicy,
                excludedCleanupTargets: excludedCleanupDeletionTargets,
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
        Task {
            await deviceViewModel.refresh()
            await refreshDeviceLibrary()
        }
    }

    private func exportAppData() {
        let panel = NSSavePanel()
        panel.title = "Back Up App Data"
        panel.nameFieldStringValue = AppDataBackupService.defaultBackupFileName()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        Task {
            do {
                let backupURL = try await Task.detached {
                    try AppDataBackupService().exportBackup(to: destinationURL)
                }.value
                appDataMessage = "Exported app data to \(backupURL.lastPathComponent)."
            } catch {
                appDataMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func exportOPMLSubscriptions() {
        let panel = NSSavePanel()
        panel.title = "Export Podcast Subscriptions"
        panel.nameFieldStringValue = "Simple Podcast Manager Subscriptions.opml"
        panel.allowedContentTypes = [opmlContentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let data = OPMLSubscriptionService().exportSubscriptions(viewModel.feedSubscriptions)
            try data.write(to: destinationURL, options: .atomic)
            appDataMessage = "Exported podcast subscriptions to \(destinationURL.lastPathComponent)."
        } catch {
            appDataMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var opmlContentType: UTType {
        UTType(filenameExtension: "opml") ?? .xml
    }

    private func openOPMLSubscriptionImport() {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else {
            appDataMessage = "Could not open the OPML file picker."
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Import Podcast Subscriptions"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let sourceURL = panel.url else { return }
            handleOPMLFile(at: sourceURL)
        }
    }

    private func handleOPMLFile(at sourceURL: URL) {
        do {
            let canAccessURL = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if canAccessURL {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: sourceURL)
            let preview = try OPMLSubscriptionService().importPreview(
                data: data,
                existingSubscriptions: viewModel.feedSubscriptions
            )
            opmlImportPreview = preview
        } catch {
            appDataMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func importOPMLSubscriptions(_ preview: OPMLSubscriptionImportPreview) throws {
        let addedSubscriptionIDs = try viewModel.importSubscriptions(preview.subscriptionsToAdd)
        opmlImportPreview = nil
        appDataMessage = "Added \(preview.subscriptionsToAdd.count) podcast subscription\(preview.subscriptionsToAdd.count == 1 ? "" : "s")."
        refreshAddedSubscriptions(withIDs: addedSubscriptionIDs)
    }

    private func importAppData() {
        let panel = NSOpenPanel()
        panel.title = "Restore App Data"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let backupURL = panel.url else { return }
        guard confirmsAppDataRestore(from: backupURL) else { return }
        appDataMessage = nil

        Task {
            do {
                let previousBackupURL = try await Task.detached {
                    try AppDataBackupService().importBackup(from: backupURL)
                }.value
                await reloadAppData()
                appDataMessage = nil
                showAppDataRestoreSuccess(previousBackupURL: previousBackupURL)
            } catch {
                appDataMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func confirmsAppDataRestore(from backupURL: URL) -> Bool {
        let confirmation = AppDataRestoreConfirmation(backupURL: backupURL)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = confirmation.title
        alert.informativeText = confirmation.message
        alert.addButton(withTitle: confirmation.cancelButtonTitle)
        let restoreButton = alert.addButton(withTitle: confirmation.restoreButtonTitle)
        restoreButton.hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func showAppDataRestoreSuccess(previousBackupURL: URL?) {
        let success = AppDataRestoreSuccess(previousBackupURL: previousBackupURL)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = success.title
        alert.informativeText = success.message
        alert.addButton(withTitle: success.doneButtonTitle)

        if let previousBackupURL = success.previousBackupURL {
            alert.addButton(withTitle: success.showBackupButtonTitle)
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([previousBackupURL])
            }
        } else {
            alert.runModal()
        }
    }

    private func reloadAppData() async {
        await viewModel.load()
        await loadPersistedEpisodeStateForStartup(forceReload: true)
        selectedFeedID = FeedSelectionPolicy.initialSelection
        manuallySelectedDeletionTargets = []
        selectedOtherAudioDeletionTargets = []
        visibleEpisodeCountsByFeedID = [:]
        expandedEpisodeIDs = []
        expandedDescriptionFeedIDs = []
        await refreshAllContent()
    }

    private func requestFeedDeletion(at offsets: IndexSet) {
        let subscriptions = offsets.compactMap { offset in
            viewModel.feedSubscriptions.indices.contains(offset) ? viewModel.feedSubscriptions[offset] : nil
        }
        guard !subscriptions.isEmpty else { return }

        pendingFeedDeletionConfirmation = FeedDeletionConfirmation(subscriptions: subscriptions)
    }

    private func confirmFeedDeletion(_ confirmation: FeedDeletionConfirmation) {
        let subscriptionIDs = Set(confirmation.subscriptionIDs)
        let offsets = IndexSet(
            viewModel.feedSubscriptions.indices.filter { index in
                subscriptionIDs.contains(viewModel.feedSubscriptions[index].id)
            }
        )
        pendingFeedDeletionConfirmation = nil
        guard !offsets.isEmpty else { return }

        deleteFeeds(at: offsets)
    }

    private func deleteFeeds(at offsets: IndexSet) {
        viewModel.removeFeeds(at: offsets)
        selectedFeedID = FeedSelectionPolicy.selectionAfterRemovingFeeds(
            currentSelection: selectedFeedID,
            remainingSubscriptions: viewModel.feedSubscriptions
        )
        Task {
            await feedActivityViewModel.updateAfterRefresh(
                subscriptions: viewModel.feedSubscriptions,
                episodes: feedPreviewViewModel.allEpisodes,
                refreshedSubscriptionIDs: [],
                failedSubscriptionIDs: [],
                openSubscriptionID: selectedFeedID
            )
            await automaticDownloadViewModel.applyPreferences(
                subscriptions: viewModel.feedSubscriptions,
                limit: viewModel.settings.automaticDownloadLimit
            )
            await refreshAllContent()
        }
    }

    private func allEpisodes(for subscription: FeedSubscription) -> [Episode] {
        feedPreviewViewModel.episodes(for: subscription.id)
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
        feedPreviewViewModel.failures(for: subscription.id)
    }

    private func artworkURL(for subscription: FeedSubscription) -> URL? {
        subscription.artworkURL ?? feedPreviewViewModel.artworkURL(for: subscription.id)
    }

    private var enabledSubscriptionCount: Int {
        viewModel.feedSubscriptions.filter(\.isEnabled).count
    }

    private var applicationErrorMessage: String? {
        viewModel.lastErrorMessage
            ?? preparationPreviewViewModel.lastErrorMessage
            ?? automaticDownloadViewModel.lastErrorMessage
            ?? feedActivityViewModel.lastErrorMessage
            ?? removedEpisodeHistoryViewModel.lastErrorMessage
    }

    private func runSync() async {
        let preparedEpisodesBeforeSync = preparationPreviewViewModel.preparedEpisodes
        let alreadyOnDeviceFilesByEpisodeKey = Dictionary(uniqueKeysWithValues: preparedEpisodesBeforeSync.compactMap { prepared -> (FeedActivityEpisodeKey, URL)? in
            guard let deviceFileURL = deviceLibraryViewModel.file(for: prepared.episode),
                  let episodeKey = FeedActivityEpisodeKey(episode: prepared.episode)
            else { return nil }
            return (episodeKey, deviceFileURL.standardizedFileURL)
        })
        let filesBySubscriptionID = Dictionary(uniqueKeysWithValues: viewModel.feedSubscriptions.map {
            ($0.id, deviceLibraryViewModel.files(for: $0))
        })
        let episodesBySubscriptionID = Dictionary(grouping: feedPreviewViewModel.allEpisodes.compactMap { episode -> (UUID, Episode)? in
            guard let subscriptionID = episode.subscriptionID else { return nil }
            return (subscriptionID, episode)
        }, by: \.0).mapValues { $0.map(\.1) }

        await syncExecutionViewModel.sync(plan: syncPlanViewModel.plan)

        if syncExecutionViewModel.lastErrorMessage == nil,
           let completedPlan = syncExecutionViewModel.lastPlan,
           syncExecutionViewModel.lastResult != nil {
            let acknowledgedEpisodes = FeedActivitySyncAcknowledgement.episodesAcknowledged(
                preparedEpisodes: preparedEpisodesBeforeSync,
                existingDeviceFiles: alreadyOnDeviceFilesByEpisodeKey,
                completedPlan: completedPlan
            )
            await feedActivityViewModel.acknowledgeSynced(acknowledgedEpisodes)
        }

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
            await deviceViewModel.refresh()
        }
        await refreshDeviceLibrary()
    }

    private func openSyncDialog() {
        syncExecutionViewModel.clearLastResult()
        isEjectAfterSyncEnabled = true
        isDeleteDownloadedAfterSyncEnabled = true
        excludedCleanupDeletionTargets = []
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

    private func toggleCleanupDeletionSelection(for fileURL: URL) {
        let fileURL = fileURL.standardizedFileURL
        let isCurrentlySelected = syncPlanViewModel.plan?.actions.contains(where: { action in
            guard case .deleteFromDevice(let targetURL, _) = action else { return false }
            return targetURL.standardizedFileURL == fileURL
        }) == true

        if isCurrentlySelected {
            excludedCleanupDeletionTargets.insert(fileURL)
            manuallySelectedDeletionTargets.remove(fileURL)
        } else {
            excludedCleanupDeletionTargets.remove(fileURL)
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
        Task {
            await automaticDownloadViewModel.applyPreferences(
                subscriptions: viewModel.feedSubscriptions,
                limit: updatedSettings.automaticDownloadLimit
            )
        }
        appearancePreference?.wrappedValue = updatedSettings.appearancePreference

        if podcastDirectoryPath != nil {
            Task {
                await deviceViewModel.refresh()
                await refreshDeviceLibrary()
            }
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

private struct EpisodeStatus {
    let preparedEpisode: PreparedEpisode?
    let downloadedRecord: DownloadedEpisodeRecord?
    let removedRecord: RemovedEpisodeRecord?
    let preparationFailure: PreparationFailure?
    let deviceFileURL: URL?
}
