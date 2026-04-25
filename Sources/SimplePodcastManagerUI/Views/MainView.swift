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
    @State private var updateCheckViewModel: UpdateCheckViewModel
    @State private var selectedFeedID: FeedSubscription.ID?
    @State private var editorDraft = FeedDraft()
    @State private var feedEditorPresentationID = UUID()
    @State private var isShowingFeedEditor = false
    @State private var isShowingSettings = false
    @State private var isShowingSyncPreview = false
    @State private var isDryRunEnabled = true
    @State private var isEjectAfterSyncEnabled = false
    @State private var isDeleteDownloadedAfterSyncEnabled = false
    @State private var isShowingDeviceDetails = false
    @State private var expandedEpisodeFeedIDs: Set<UUID> = []
    @State private var expandedDescriptionFeedIDs: Set<UUID> = []
    @State private var isHoveringDeviceStatus = false
    @State private var hoveringEpisodeToggleFeedID: UUID?
    @State private var manuallySelectedDeletionTargets: Set<URL> = []
    @State private var appDataMessage: String?

    public init(viewModel: MainViewModel) {
        self._viewModel = State(initialValue: viewModel)
        self._deviceViewModel = State(initialValue: DeviceViewModel())
        self._deviceLibraryViewModel = State(initialValue: DeviceLibraryViewModel())
        self._feedPreviewViewModel = State(initialValue: FeedPreviewViewModel())
        self._preparationPreviewViewModel = State(initialValue: PreparationPreviewViewModel())
        self._removedEpisodeHistoryViewModel = State(initialValue: RemovedEpisodeHistoryViewModel())
        self._syncPlanViewModel = State(initialValue: SyncPlanViewModel())
        self._syncExecutionViewModel = State(initialValue: SyncExecutionViewModel())
        self._updateCheckViewModel = State(initialValue: UpdateCheckViewModel())
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

            if let appDataMessage {
                Text(appDataMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if updateCheckViewModel.isChecking {
                Text("Checking for updates...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            if !removedEpisodeHistoryViewModel.hasLoadedRemovedEpisodes {
                removedEpisodeHistoryViewModel.load()
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
            .id(feedEditorPresentationID)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: viewModel.settings) { updatedSettings in
                viewModel.replaceSettings(updatedSettings)
            }
        }
        .sheet(isPresented: $isShowingSyncPreview) {
            syncPreviewSheet
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
        .onReceive(NotificationCenter.default.publisher(for: .simplePodcastManagerCheckForUpdates)) { _ in
            Task { await updateCheckViewModel.checkForUpdates() }
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
        .alert(updateAlertTitle, isPresented: updateAlertBinding) {
            if let releaseURL = updateReleaseURL {
                Button("Open Release") {
                    NSWorkspace.shared.open(releaseURL)
                    updateCheckViewModel.clearResult()
                }
            }
            Button("OK") {
                updateCheckViewModel.clearResult()
            }
        } message: {
            Text(updateAlertMessage)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device")
                        .font(.headline)
                    if let selectedDevice = deviceViewModel.selectedDevice {
                        Button(deviceViewModel.statusMessage) {
                            isShowingDeviceDetails.toggle()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isHoveringDeviceStatus ? Color.blue : Color.white)
                        .onHover { isHoveringDeviceStatus = $0 }
                        .popover(isPresented: $isShowingDeviceDetails, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(selectedDevice.name)
                                    .font(.headline)
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
                            .padding(12)
                            .frame(minWidth: 320, alignment: .leading)
                        }
                    } else {
                        Text(deviceViewModel.statusMessage)
                            .foregroundStyle(.secondary)
                    }
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

                HoverIconButton(
                    systemName: "arrow.clockwise",
                    helpText: "Refresh devices"
                ) {
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

            if viewModel.hasFeeds {
                syncControlsRow
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
                    feedEditorPresentationID = UUID()
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

                            Text("\(allEpisodes(for: subscription).count) episode\(allEpisodes(for: subscription).count == 1 ? "" : "s")")
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
                                    feedEditorPresentationID = UUID()
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

                            podcastDescriptionSection(for: selectedSubscription)
                        }
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button(preparationPreviewViewModel.isPreparing ? "Downloading..." : "Download All") {
                            Task {
                                await preparationPreviewViewModel.prepare(syncSelectedEpisodes(for: selectedSubscription), settings: viewModel.settings)
                                rebuildSyncPlan()
                            }
                        }
                        .disabled(preparationPreviewViewModel.isPreparing || syncSelectedEpisodes(for: selectedSubscription).isEmpty)
                    }
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

                if allEpisodes(for: selectedSubscription).isEmpty {
                    ContentUnavailableView(
                        "No Episodes Yet",
                        systemImage: "waveform",
                        description: Text("Refresh feeds to load the latest retained episodes for this show.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if shouldOfferEpisodeExpansion(for: selectedSubscription) {
                        Button(isShowingAllEpisodes(for: selectedSubscription) ? "Show recent" : "Show all (\(allEpisodes(for: selectedSubscription).count))") {
                            toggleEpisodeExpansion(for: selectedSubscription)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(hoveringEpisodeToggleFeedID == selectedSubscription.id ? Color.blue : Color.white)
                        .onHover { isHovering in
                            hoveringEpisodeToggleFeedID = isHovering ? selectedSubscription.id : nil
                        }
                    }

                    List {
                        ForEach(displayedEpisodes(for: selectedSubscription)) { episode in
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

                Button("Preview Sync") {
                    openSyncPreview()
                }
                .disabled(!canOpenSyncPreview)
            }

            if let progress = syncExecutionViewModel.progress, syncExecutionViewModel.isSyncing {
                syncProgressSection(progress)
            }

            if let lastResult = syncExecutionViewModel.lastResult {
                Text(syncResultSummary(lastResult))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var syncPreviewSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync Preview")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(syncPlanSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close") {
                    isShowingSyncPreview = false
                }

                Button(sheetSyncButtonTitle) {
                    Task {
                        await runSync()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSync)
            }

            Toggle("Preview only (dry run)", isOn: $isDryRunEnabled)
                .toggleStyle(.checkbox)
                .onChange(of: isDryRunEnabled) {
                    rebuildSyncPlan()
                }

            Toggle("Eject after sync", isOn: $isEjectAfterSyncEnabled)
                .toggleStyle(.checkbox)
                .onChange(of: isEjectAfterSyncEnabled) {
                    rebuildSyncPlan()
                }

            Toggle("Delete downloaded episodes after sync", isOn: $isDeleteDownloadedAfterSyncEnabled)
                .toggleStyle(.checkbox)
                .disabled(isDryRunEnabled)

            if let progress = syncExecutionViewModel.progress, syncExecutionViewModel.isSyncing {
                syncProgressSection(progress)
            }

            if let lastResult = syncExecutionViewModel.lastResult {
                syncResultCard(lastResult)
            }

            syncSummaryCard

            if !syncPlanViewModel.actionDescriptions.isEmpty {
                plannedActionsSection
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
    }

    @ViewBuilder
    private var syncSummaryCard: some View {
        let plan = syncPlanViewModel.plan
        let preparedCount = preparationPreviewViewModel.preparedEpisodes.count

        VStack(alignment: .leading, spacing: 8) {
            Text("Plan Summary")
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

                Text("\(preparedCount) episode\(preparedCount == 1 ? "" : "s") ready across \(enabledSubscriptionCount) show\(enabledSubscriptionCount == 1 ? "" : "s"), \(copyCount) to copy, \(skipCount) to skip, \(deleteCount) to delete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Choose a compatible device to build the full sync plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var plannedActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Planned Actions")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(syncPlanViewModel.actionDescriptions.enumerated()), id: \.offset) { _, description in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: iconName(for: description))
                                .foregroundStyle(iconColor(for: description))
                                .frame(width: 14)
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(minHeight: 100, maxHeight: 180)
        }
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
                    Text(downloadedEpisodeLabel(for: preparedEpisode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let downloadedRecord = preparationPreviewViewModel.downloadedRecord(for: episode) {
                    Text(downloadedEpisodeLabel(for: downloadedRecord))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let removedRecord = removedEpisodeHistoryViewModel.removedRecord(for: episode) {
                    Text(removedEpisodeLabel(for: removedRecord))
                        .font(.caption)
                        .foregroundStyle(.orange)
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

    private var updateAlertBinding: Binding<Bool> {
        Binding(
            get: {
                updateCheckViewModel.latestResult != nil || updateCheckViewModel.lastErrorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    updateCheckViewModel.clearResult()
                }
            }
        )
    }

    private var updateAlertTitle: String {
        if let result = updateCheckViewModel.latestResult {
            return result.isUpdateAvailable ? "Update Available" : "Simple Podcast Manager Is Up to Date"
        }
        return "Could Not Check for Updates"
    }

    private var updateAlertMessage: String {
        if let result = updateCheckViewModel.latestResult {
            if result.isUpdateAvailable {
                return "\(result.latestRelease.name) is available. You are running \(updateCheckViewModel.displayVersion)."
            }

            return "You are running the latest release: \(result.latestRelease.name)."
        }

        return updateCheckViewModel.lastErrorMessage ?? "Try again later."
    }

    private var updateReleaseURL: URL? {
        guard let result = updateCheckViewModel.latestResult, result.isUpdateAvailable else {
            return nil
        }
        return result.latestRelease.htmlURL
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
            manualDeleteTargets: manuallySelectedDeletionTargets,
            ejectAfterSync: isEjectAfterSyncEnabled,
            isDryRun: isDryRunEnabled
        )
    }

    private func refreshDeviceLibrary() {
        deviceLibraryViewModel.refresh(
            device: deviceViewModel.selectedDevice,
            subscriptions: viewModel.feedSubscriptions
        )
        pruneManualDeletionTargets()
    }

    private func handleDeviceTopologyChange() {
        deviceViewModel.refresh()
        refreshDeviceLibrary()
        rebuildSyncPlan()
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
        expandedEpisodeFeedIDs = []
        expandedDescriptionFeedIDs = []
        Task { await refreshFeedPreview() }
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

    private func allEpisodes(for subscription: FeedSubscription) -> [Episode] {
        feedPreviewViewModel.allEpisodes
            .filter { $0.subscriptionID == subscription.id }
            .sorted(by: EpisodeSelector.isHigherPriority(_:than:))
    }

    private func displayedEpisodes(for subscription: FeedSubscription) -> [Episode] {
        let episodes = allEpisodes(for: subscription)
        if isShowingAllEpisodes(for: subscription) {
            return episodes
        }
        return Array(episodes.prefix(8))
    }

    private func isShowingAllEpisodes(for subscription: FeedSubscription) -> Bool {
        expandedEpisodeFeedIDs.contains(subscription.id)
    }

    private func shouldOfferEpisodeExpansion(for subscription: FeedSubscription) -> Bool {
        allEpisodes(for: subscription).count > 8
    }

    private func toggleEpisodeExpansion(for subscription: FeedSubscription) {
        if expandedEpisodeFeedIDs.contains(subscription.id) {
            expandedEpisodeFeedIDs.remove(subscription.id)
        } else {
            expandedEpisodeFeedIDs.insert(subscription.id)
        }
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

    private func syncSelectedEpisodes(for subscription: FeedSubscription) -> [Episode] {
        feedPreviewViewModel.selectedEpisodes
            .filter { $0.subscriptionID == subscription.id }
            .sorted(by: EpisodeSelector.isHigherPriority(_:than:))
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

    private var canOpenSyncPreview: Bool {
        deviceViewModel.selectedDevice != nil && !viewModel.feedSubscriptions.isEmpty
    }

    private var enabledSubscriptionCount: Int {
        viewModel.feedSubscriptions.filter(\.isEnabled).count
    }

    private var syncPlanSummaryText: String {
        guard let plan = syncPlanViewModel.plan else {
            return deviceViewModel.selectedDevice == nil
                ? "Pick a compatible device to preview the full sync."
                : "The full sync plan will appear here once episodes are prepared."
        }

        let actionCount = plan.actions.count
        return "Review the full-device plan for all shows before \(plan.isDryRun ? "previewing" : "syncing"). \(actionCount) action\(actionCount == 1 ? "" : "s") currently planned."
    }

    @ViewBuilder
    private func syncProgressSection(_ progress: SyncExecutionProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(progress.currentActionDescription ?? "Finishing sync")
                .font(.subheadline)
                .fontWeight(.medium)
            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
            Text("\(progress.completedCount) of \(progress.totalCount) actions complete")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func syncResultCard(_ result: SyncResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.isDryRun ? "Last Preview" : "Last Sync")
                .font(.headline)

            Text(syncResultSummary(result))
                .font(.caption)
                .foregroundStyle(.secondary)

            if result.ejected {
                Text("The device was ejected after the sync finished.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(result.warnings, id: \.self) { warning in
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func iconName(for description: String) -> String {
        if description.hasPrefix("Copy to device") {
            return "arrow.down.circle"
        }
        if description.hasPrefix("Delete old episode") {
            return "trash"
        }
        if description.hasPrefix("Skip") {
            return "arrow.right"
        }
        if description == "Clear device trash" {
            return "trash.slash"
        }
        if description == "Eject device after sync" {
            return "eject"
        }
        return "circle"
    }

    private func iconColor(for description: String) -> Color {
        if description.hasPrefix("Delete old episode") {
            return .red
        }
        if description.hasPrefix("Copy to device") {
            return .accentColor
        }
        if description == "Clear device trash" {
            return .orange
        }
        if description == "Eject device after sync" {
            return .secondary
        }
        return .secondary
    }

    private func runSync() async {
        let filesBySubscriptionID = Dictionary(uniqueKeysWithValues: viewModel.feedSubscriptions.map {
            ($0.id, deviceLibraryViewModel.files(for: $0))
        })
        let episodesBySubscriptionID = Dictionary(grouping: feedPreviewViewModel.allEpisodes.compactMap { episode -> (UUID, Episode)? in
            guard let subscriptionID = episode.subscriptionID else { return nil }
            return (subscriptionID, episode)
        }, by: \.0).mapValues { $0.map(\.1) }

        await syncExecutionViewModel.sync(
            device: deviceViewModel.selectedDevice,
            preparedEpisodes: preparationPreviewViewModel.preparedEpisodes,
            subscriptions: viewModel.feedSubscriptions,
            manualDeleteTargets: manuallySelectedDeletionTargets,
            ejectAfterSync: isEjectAfterSyncEnabled,
            isDryRun: isDryRunEnabled
        )

        if
            let result = syncExecutionViewModel.lastResult,
            !result.isDryRun,
            let lastPlan = syncExecutionViewModel.lastPlan
        {
            let deletedTargetURLs = lastPlan.actions.compactMap { action -> URL? in
                guard case .deleteFromDevice(let targetURL) = action else { return nil }
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
            let result = syncExecutionViewModel.lastResult,
            !result.isDryRun
        {
            preparationPreviewViewModel.removeAllPreparedEpisodes()
        }

        refreshDeviceLibrary()
        rebuildSyncPlan()
        if viewModel.hasFeeds {
            await refreshFeedPreview()
        }
        if isEjectAfterSyncEnabled {
            deviceViewModel.refresh()
        }
    }

    private func openSyncPreview() {
        rebuildSyncPlan()
        isShowingSyncPreview = true
    }

    private func removedEpisodeLabel(for record: RemovedEpisodeRecord) -> String {
        let removedDate = record.removedAt.formatted(date: .abbreviated, time: .omitted)
        let deviceName = record.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let deviceName, !deviceName.isEmpty {
            return "Removed from \(deviceName) \(removedDate)"
        }
        return "Removed from device \(removedDate)"
    }

    private func downloadedEpisodeLabel(for preparedEpisode: PreparedEpisode) -> String {
        let actionText = preparedEpisode.preparationAction == .passthroughMP3 ? "MP3" : "converted to MP3"
        guard let preparedAt = preparedEpisode.preparedAt else {
            return "Downloaded previously (\(actionText))"
        }
        let downloadedDate = preparedAt.formatted(date: .abbreviated, time: .omitted)
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

    private func pruneManualDeletionTargets() {
        let allKnownFiles = Set(
            viewModel.feedSubscriptions
                .flatMap { deviceLibraryViewModel.files(for: $0) }
                .map(\.standardizedFileURL)
        )
        manuallySelectedDeletionTargets = manuallySelectedDeletionTargets.intersection(allKnownFiles)
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
                Text(isDryRunEnabled
                    ? "Checked files stay on the device. Uncheck a file to preview deleting it."
                    : "Checked files stay on the device. Uncheck a file to delete it on the next sync.")
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

    private func syncResultSummary(_ result: SyncResult) -> String {
        let finishedText = result.finishedAt?.formatted(date: .omitted, time: .shortened) ?? "now"
        if result.isDryRun {
            return "Last dry run at \(finishedText): \(result.copiedCount) would copy, \(result.deletedCount) would delete, \(result.skippedCount) would skip."
        }
        return "Last sync at \(finishedText): \(result.copiedCount) copied, \(result.deletedCount) deleted, \(result.skippedCount) skipped."
    }

    private var sheetSyncButtonTitle: String {
        if syncExecutionViewModel.isSyncing {
            return isDryRunEnabled ? "Previewing..." : "Syncing..."
        }
        return isDryRunEnabled ? "Run Preview" : "Start Sync"
    }
}
