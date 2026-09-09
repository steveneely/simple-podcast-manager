import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct AppWorkflowsTests {
    @Test
    func partialSyncRecordsOnlyCompletedDeletionsAndKeepsLocalAudio() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        let episode = fixture.episode("old")
        let pending = fixture.episode("pending")
        let prepared = try fixture.prepareLocally(episode)
        try await fixture.preparation.applyPersistedState(preparedEpisodes: [prepared], downloadedEpisodes: [])
        let target = fixture.deviceFile(for: episode)
        let pendingTarget = fixture.deviceFile(for: pending)
        let inventory = DeviceLibraryViewModel(deviceLibrary: WorkflowDeviceLibrary(files: [target, pendingTarget]))
        await inventory.refresh(device: fixture.device, subscriptions: [fixture.podcast], episodes: [episode, pending])
        let deletion = SyncAction.deleteFromDevice(targetURL: target, fileSizeBytes: 5)
        let result = SyncResult(deletedCount: 1, completedActions: [deletion])
        let execution = SyncExecutionViewModel(executor: WorkflowExecutor(result: .failure(SyncExecutionFailure(result: result, underlyingError: CocoaError(.fileWriteUnknown)))))
        let workflow = fixture.syncWorkflow(execution: execution, inventory: inventory)
        let succeeded = await workflow.run(
            plan: SyncPlan(device: fixture.device, actions: [deletion, .deleteFromDevice(targetURL: pendingTarget, fileSizeBytes: 5)]),
            subscriptions: [fixture.podcast], episodes: [episode, pending], deleteDownloadsAfterSync: true
        )
        #expect(!succeeded)
        #expect(fixture.removalHistory.removedRecord(for: episode) != nil)
        #expect(fixture.removalHistory.removedRecord(for: pending) == nil)
        #expect(try fixture.store.loadRemovedEpisodes().count == 1)
        #expect(FileManager.default.fileExists(atPath: prepared.preparedFileURL.path))
    }

    @Test
    func successfulSyncRemovesOnlyLocalAudioAcknowledgedByTheReviewedPlan() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        let copied = try fixture.prepareLocally(fixture.episode("copied"))
        let untouched = try fixture.prepareLocally(fixture.episode("not-in-plan"))
        try await fixture.preparation.applyPersistedState(preparedEpisodes: [copied, untouched], downloadedEpisodes: [])
        let copy = SyncAction.copyToDevice(sourceURL: copied.preparedFileURL, destinationURL: fixture.deviceFile(for: copied.episode), fileSizeBytes: 5)
        let execution = SyncExecutionViewModel(executor: WorkflowExecutor(result: .success(SyncResult(copiedCount: 1, completedActions: [copy]))))
        let succeeded = await fixture.syncWorkflow(execution: execution).run(
            plan: SyncPlan(device: fixture.device, actions: [copy]), subscriptions: [fixture.podcast],
            episodes: [copied.episode, untouched.episode], deleteDownloadsAfterSync: true
        )
        #expect(succeeded)
        #expect(!FileManager.default.fileExists(atPath: copied.preparedFileURL.path))
        #expect(FileManager.default.fileExists(atPath: untouched.preparedFileURL.path))
        #expect(fixture.preparation.preparedEpisodes == [untouched])
    }

    @Test
    func restoreLoadsConfigurationAndAllEpisodeStateBeforeReportingSuccess() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        let backup = fixture.root.appendingPathComponent("test.spmbackup")
        let configuration = JSONConfigurationStore(fileURL: fixture.root.appendingPathComponent("config.json"))
        try configuration.saveConfiguration(AppConfiguration(settings: AppSettings(mp3Genre: "Restored"), podcastSubscriptions: [fixture.podcast]))
        let prepared = try fixture.prepareLocally(fixture.episode("restored"))
        try fixture.store.savePreparedEpisodes([prepared])
        let previous = try await fixture.appDataWorkflow().restore(from: backup, importBackup: { _ in backup })
        #expect(previous == backup)
        #expect(fixture.library.settings.mp3Genre == "Restored")
        #expect(fixture.preparation.preparedEpisodes == [prepared])
        #expect(fixture.automaticDownloads.hasLoadedState)
        #expect(fixture.activity.hasLoadedState)
        #expect(fixture.removalHistory.hasLoadedRemovedEpisodes)
    }

    @Test
    func failedSnapshotDoesNotApplyEmptyBaselinesOrReportRestoreSuccess() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        let workflow = fixture.appDataWorkflow(episodeStore: FailingSnapshotStore())
        await #expect(throws: (any Error).self) { try await workflow.loadEpisodeState() }
        #expect(!fixture.automaticDownloads.hasLoadedState)
        #expect(!fixture.activity.hasLoadedState)
        await #expect(throws: (any Error).self) {
            try await workflow.restore(from: fixture.root, importBackup: { _ in nil })
        }
        #expect(!fixture.removalHistory.hasLoadedRemovedEpisodes)
    }
}

@MainActor
private struct WorkflowFixture {
    let root: URL
    let store: SQLiteEpisodeStore
    let library: MainViewModel
    let preparation: PreparationPreviewViewModel
    let automaticDownloads: AutomaticDownloadViewModel
    let activity: PodcastActivityViewModel
    let removalHistory: RemovedEpisodeHistoryViewModel
    let podcast = PodcastSubscription(title: "Workflow Podcast", rssURL: URL(string: "https://example.com/rss")!)
    let device = DeviceInfo(name: "Test", rootURL: URL(fileURLWithPath: "/Volumes/WORKFLOW-TEST"), podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WORKFLOW-TEST/music"))

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = SQLiteEpisodeStore(fileURL: root.appendingPathComponent("episodes.sqlite3"))
        library = MainViewModel(store: JSONConfigurationStore(fileURL: root.appendingPathComponent("config.json")))
        preparation = PreparationPreviewViewModel(store: store, downloadedEpisodeStore: store)
        automaticDownloads = AutomaticDownloadViewModel(store: store)
        activity = PodcastActivityViewModel(store: store)
        removalHistory = RemovedEpisodeHistoryViewModel(store: store)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func episode(_ id: String) -> Episode {
        Episode(id: id, subscriptionID: podcast.id, podcastTitle: podcast.title, title: id,
                enclosureURL: URL(string: "https://example.com/\(id).mp3")!, sourceFeedURL: podcast.rssURL)
    }
    func deviceFile(for episode: Episode) -> URL {
        device.podcastDirectoryURL.appendingPathComponent(EpisodeFileName.directoryName(for: podcast)).appendingPathComponent(EpisodeFileName.fileName(for: episode, fileExtension: "mp3"))
    }
    func prepareLocally(_ episode: Episode) throws -> PreparedEpisode {
        let url = root.appendingPathComponent("\(episode.id).mp3")
        try Data("audio".utf8).write(to: url)
        return PreparedEpisode(episode: episode, sourceFileURL: url, preparedFileURL: url, preparationAction: .passthroughMP3, preparedAt: Date(timeIntervalSince1970: 100))
    }
    func appDataWorkflow(episodeStore: (any EpisodeStateLoading)? = nil) -> AppDataWorkflow {
        AppDataWorkflow(library: library, preparation: preparation, automaticDownloads: automaticDownloads, activity: activity, removalHistory: removalHistory, episodeStore: episodeStore ?? store)
    }
    func syncWorkflow(execution: SyncExecutionViewModel, inventory: DeviceLibraryViewModel = DeviceLibraryViewModel()) -> SyncWorkflow {
        SyncWorkflow(execution: execution, preparation: preparation, activity: activity, removalHistory: removalHistory, deviceLibrary: inventory)
    }
}

private struct WorkflowExecutor: SyncExecuting {
    let result: Result<SyncResult, any Error>
    func execute(plan: SyncPlan, progress: (@Sendable (SyncExecutionProgress) -> Void)?) throws -> SyncResult { try result.get() }
}
private struct WorkflowDeviceLibrary: DeviceLibraryInspecting {
    let files: [URL]
    func files(in directoryURL: URL) throws -> [URL] { files.filter { $0.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL } }
    func containsSupportedAudioFile(in directoryURL: URL, excluding fileURLs: Set<URL>) throws -> Bool { false }
}
private struct FailingSnapshotStore: EpisodeStateLoading {
    func loadEpisodeStateSnapshot() throws -> EpisodeStateSnapshot { throw CocoaError(.fileReadCorruptFile) }
}
