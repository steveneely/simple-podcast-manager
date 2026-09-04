import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct PreparationPreviewViewModelTests {
    @Test
    func prepareLoadsPreparedEpisodesAndFailures() async throws {
        let workspaceURL = URL(fileURLWithPath: "/tmp/simple-podcast-manager-workspace", isDirectory: true)
        let store = InMemoryPreparedEpisodeStore()
        let downloadedStore = InMemoryDownloadedEpisodeStore()
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: StubPreparationDownloadService(),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: workspaceURL)
            ),
            store: store,
            downloadedEpisodeStore: downloadedStore
        )
        let episode = Episode(
            id: "ep-1",
            subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            podcastTitle: "Example Podcast",
            title: "Episode 1",
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )

        await viewModel.prepare([episode], settings: AppSettings())

        #expect(viewModel.preparedEpisodes.count == 1)
        #expect(viewModel.failure(for: episode) == nil)
        #expect(store.preparedEpisodes.count == 1)
        #expect(downloadedStore.downloadedEpisodes.count == 1)
        #expect(downloadedStore.downloadedEpisodes.first?.episodeID == "ep-1")
    }

    @Test
    func loadsPersistedPreparedEpisodesOnLaunch() async throws {
        let existingFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try Data("audio".utf8).write(to: existingFileURL)
        defer { try? FileManager.default.removeItem(at: existingFileURL) }

        let episode = Episode(
            id: "ep-1",
            podcastTitle: "Example Podcast",
            title: "Episode 1",
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let preparedEpisode = PreparedEpisode(
            episode: episode,
            sourceFileURL: existingFileURL,
            preparedFileURL: existingFileURL,
            preparationAction: .passthroughMP3
        )
        let store = InMemoryPreparedEpisodeStore(preparedEpisodes: [preparedEpisode])
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: StubPreparationDownloadService(),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: URL(fileURLWithPath: "/tmp/simple-podcast-manager-workspace", isDirectory: true))
            ),
            store: store
        )

        await viewModel.loadPersistedPreparedEpisodes()

        #expect(viewModel.hasLoadedPreparedEpisodes)
        #expect(viewModel.preparedEpisodes == [preparedEpisode])
    }

    @Test
    func loadsPersistedDownloadedEpisodeHistory() async throws {
        let subscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let downloadedRecord = DownloadedEpisodeRecord(
            subscriptionID: subscriptionID,
            episodeID: "ep-1",
            episodeTitle: "Episode 1",
            preparationAction: .passthroughMP3,
            downloadedAt: Date(timeIntervalSince1970: 0)
        )
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: StubPreparationDownloadService(),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: URL(fileURLWithPath: "/tmp/simple-podcast-manager-workspace", isDirectory: true))
            ),
            store: InMemoryPreparedEpisodeStore(),
            downloadedEpisodeStore: InMemoryDownloadedEpisodeStore(downloadedEpisodes: [downloadedRecord])
        )
        let episode = Episode(
            id: "ep-1",
            subscriptionID: subscriptionID,
            podcastTitle: "Example Podcast",
            title: "Episode 1",
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )

        await viewModel.loadPersistedPreparedEpisodes()

        #expect(viewModel.downloadedRecord(for: episode) == downloadedRecord)
    }

    @Test
    func removeAllPreparedEpisodesDeletesLocalFilesAndPersistsEmptyState() async throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source.m4a")
        let preparedURL = temporaryDirectoryURL.appendingPathComponent("prepared.mp3")
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: sourceURL)
        try Data("prepared".utf8).write(to: preparedURL)
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let episode = Episode(
            id: "ep-1",
            podcastTitle: "Example Podcast",
            title: "Episode 1",
            enclosureURL: URL(string: "https://cdn.example.com/episode.m4a")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let preparedEpisode = PreparedEpisode(
            episode: episode,
            sourceFileURL: sourceURL,
            preparedFileURL: preparedURL,
            preparationAction: .convertedToMP3
        )
        let store = InMemoryPreparedEpisodeStore(preparedEpisodes: [preparedEpisode])
        let downloadedStore = InMemoryDownloadedEpisodeStore(
            downloadedEpisodes: [
                DownloadedEpisodeRecord(
                    subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    episodeID: "ep-1",
                    episodeTitle: "Episode 1",
                    preparationAction: .convertedToMP3,
                    downloadedAt: Date(timeIntervalSince1970: 0)
                )
            ]
        )
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: StubPreparationDownloadService(),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: temporaryDirectoryURL)
            ),
            store: store,
            downloadedEpisodeStore: downloadedStore
        )
        await viewModel.loadPersistedPreparedEpisodes()

        await viewModel.removeAllPreparedEpisodes()

        #expect(viewModel.preparedEpisodes.isEmpty)
        #expect(!downloadedStore.downloadedEpisodes.isEmpty)
        #expect(store.preparedEpisodes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(!FileManager.default.fileExists(atPath: preparedURL.path))
    }

    @Test
    func removingSubscriptionDownloadsDeletesOnlyMatchingLocalFilesAndRecords() async throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let removedFileURL = temporaryDirectoryURL.appendingPathComponent("removed.mp3")
        let retainedFileURL = temporaryDirectoryURL.appendingPathComponent("retained.mp3")
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        try Data("removed".utf8).write(to: removedFileURL)
        try Data("retained".utf8).write(to: retainedFileURL)
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let removedSubscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let retainedSubscriptionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let removedEpisode = makeEpisode(
            id: "removed",
            subscriptionID: removedSubscriptionID
        )
        let retainedEpisode = makeEpisode(
            id: "retained",
            subscriptionID: retainedSubscriptionID
        )
        let removedPreparedEpisode = PreparedEpisode(
            episode: removedEpisode,
            sourceFileURL: removedFileURL,
            preparedFileURL: removedFileURL,
            preparationAction: .passthroughMP3
        )
        let retainedPreparedEpisode = PreparedEpisode(
            episode: retainedEpisode,
            sourceFileURL: retainedFileURL,
            preparedFileURL: retainedFileURL,
            preparationAction: .passthroughMP3
        )
        let preparedStore = InMemoryPreparedEpisodeStore(
            preparedEpisodes: [removedPreparedEpisode, retainedPreparedEpisode]
        )
        let downloadedStore = InMemoryDownloadedEpisodeStore(downloadedEpisodes: [
            makeDownloadedRecord(episode: removedEpisode),
            makeDownloadedRecord(episode: retainedEpisode),
        ])
        let viewModel = makeViewModel(
            workspaceURL: temporaryDirectoryURL,
            preparedStore: preparedStore,
            downloadedStore: downloadedStore
        )
        await viewModel.loadPersistedPreparedEpisodes()

        let didRemoveDownloads = await viewModel.removeDownloads(
            forSubscriptionIDs: [removedSubscriptionID]
        )

        #expect(didRemoveDownloads)
        #expect(viewModel.preparedEpisodes == [retainedPreparedEpisode])
        #expect(preparedStore.preparedEpisodes == [retainedPreparedEpisode])
        #expect(downloadedStore.downloadedEpisodes.map(\.subscriptionID) == [retainedSubscriptionID])
        #expect(!FileManager.default.fileExists(atPath: removedFileURL.path))
        #expect(FileManager.default.fileExists(atPath: retainedFileURL.path))
    }

    @Test
    func failedSubscriptionDownloadDeletionKeepsItsRecordsForRetry() async throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("episode.mp3")
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let subscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let episode = makeEpisode(id: "episode", subscriptionID: subscriptionID)
        let preparedEpisode = PreparedEpisode(
            episode: episode,
            sourceFileURL: fileURL,
            preparedFileURL: fileURL,
            preparationAction: .passthroughMP3
        )
        let preparedStore = InMemoryPreparedEpisodeStore(preparedEpisodes: [preparedEpisode])
        let downloadedStore = InMemoryDownloadedEpisodeStore(
            downloadedEpisodes: [makeDownloadedRecord(episode: episode)]
        )
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: StubPreparationDownloadService(),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: temporaryDirectoryURL)
            ),
            store: preparedStore,
            downloadedEpisodeStore: downloadedStore,
            fileDeleter: FailingPreparedMediaFileDeleter()
        )
        await viewModel.loadPersistedPreparedEpisodes()

        let didRemoveDownloads = await viewModel.removeDownloads(
            forSubscriptionIDs: [subscriptionID]
        )

        #expect(!didRemoveDownloads)
        #expect(viewModel.preparedEpisodes == [preparedEpisode])
        #expect(preparedStore.preparedEpisodes == [preparedEpisode])
        #expect(downloadedStore.downloadedEpisodes.count == 1)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(viewModel.lastErrorMessage?.contains("Could not delete the downloaded files") == true)
    }

    @Test
    func failedLocalFileDeletionRetainsPreparedEpisodeAndReportsError() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try Data("audio".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let episode = Episode(
            id: "ep-1",
            podcastTitle: "Example Podcast",
            title: "Episode 1",
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let preparedEpisode = PreparedEpisode(
            episode: episode,
            sourceFileURL: fileURL,
            preparedFileURL: fileURL,
            preparationAction: .passthroughMP3
        )
        let store = InMemoryPreparedEpisodeStore(preparedEpisodes: [preparedEpisode])
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: StubPreparationDownloadService(),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(
                    workspaceURL: FileManager.default.temporaryDirectory
                )
            ),
            store: store,
            downloadedEpisodeStore: InMemoryDownloadedEpisodeStore(),
            fileDeleter: FailingPreparedMediaFileDeleter()
        )
        await viewModel.loadPersistedPreparedEpisodes()

        await viewModel.removeAllPreparedEpisodes()

        #expect(viewModel.preparedEpisodes == [preparedEpisode])
        #expect(store.preparedEpisodes == [preparedEpisode])
        #expect(viewModel.lastErrorMessage?.contains("Could not delete the downloaded files for \"Episode 1\"") == true)
    }

    @Test
    func tracksPreparingStateForEachEpisode() async throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: DelayedPreparationDownloadService(),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: workspaceURL),
                maximumConcurrentPreparations: 1
            ),
            store: InMemoryPreparedEpisodeStore(),
            downloadedEpisodeStore: InMemoryDownloadedEpisodeStore()
        )
        let episodes = [
            Episode(
                id: "ep-1",
                subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                podcastTitle: "Example Podcast",
                title: "Episode 1",
                enclosureURL: URL(string: "https://cdn.example.com/episode1.mp3")!,
                sourceFeedURL: URL(string: "https://example.com/feed.xml")!
            ),
            Episode(
                id: "ep-2",
                subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                podcastTitle: "Example Podcast",
                title: "Episode 2",
                enclosureURL: URL(string: "https://cdn.example.com/episode2.mp3")!,
                sourceFeedURL: URL(string: "https://example.com/feed.xml")!
            )
        ]

        let preparationTask = Task {
            await viewModel.prepare(episodes, settings: AppSettings())
        }

        while !viewModel.isPreparing {
            await Task.yield()
        }

        #expect(viewModel.preparingEpisodeCount == 2)
        #expect(viewModel.isPreparing(episodes[0]))
        #expect(viewModel.isPreparing(episodes[1]))

        await preparationTask.value

        #expect(!viewModel.isPreparing)
        #expect(viewModel.preparingEpisodeCount == 0)
        #expect(!viewModel.isPreparing(episodes[0]))
        #expect(!viewModel.isPreparing(episodes[1]))
        #expect(viewModel.preparedEpisodes.count == 2)
    }

    @Test
    func preparingStateIsScopedToItsPodcast() async throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let downloadGate = PreparationDownloadGate()
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: SuspendedPreparationDownloadService(gate: downloadGate),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: workspaceURL)
            ),
            store: InMemoryPreparedEpisodeStore(),
            downloadedEpisodeStore: InMemoryDownloadedEpisodeStore()
        )
        let firstPodcastEpisode = Episode(
            id: "shared-guid",
            subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            podcastTitle: "First Podcast",
            title: "First Episode",
            enclosureURL: URL(string: "https://cdn.example.com/first.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/first.xml")!
        )
        let secondPodcastEpisode = Episode(
            id: "shared-guid",
            subscriptionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            podcastTitle: "Second Podcast",
            title: "Second Episode",
            enclosureURL: URL(string: "https://cdn.example.com/second.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/second.xml")!
        )

        let preparationTask = Task {
            await viewModel.prepare([firstPodcastEpisode], settings: AppSettings())
        }

        while !(await downloadGate.hasStarted) {
            await Task.yield()
        }

        #expect(viewModel.isPreparing(firstPodcastEpisode))
        #expect(!viewModel.isPreparing(secondPodcastEpisode))

        await downloadGate.allowDownload()
        await preparationTask.value

        #expect(viewModel.preparedEpisode(for: firstPodcastEpisode) != nil)
        #expect(viewModel.preparedEpisode(for: secondPodcastEpisode) == nil)
    }

    @Test
    func cancellingOneDownloadLeavesOtherDownloadsRunning() async throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: CancellablePreparationDownloadService(cancelledEpisodeID: "cancel-me"),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: workspaceURL)
            ),
            store: InMemoryPreparedEpisodeStore(),
            downloadedEpisodeStore: InMemoryDownloadedEpisodeStore()
        )
        let cancelledEpisode = Episode(
            id: "cancel-me",
            subscriptionID: UUID(),
            podcastTitle: "Example Podcast",
            title: "Cancel Me",
            enclosureURL: URL(string: "https://cdn.example.com/cancel.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let completedEpisode = Episode(
            id: "keep-going",
            subscriptionID: UUID(),
            podcastTitle: "Another Podcast",
            title: "Keep Going",
            enclosureURL: URL(string: "https://cdn.example.com/keep.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/another.xml")!
        )

        let preparationTask = Task {
            await viewModel.prepare([cancelledEpisode, completedEpisode], settings: AppSettings())
        }
        while !viewModel.isPreparing(cancelledEpisode) {
            await Task.yield()
        }

        viewModel.cancelPreparation(for: cancelledEpisode)
        await preparationTask.value

        #expect(!viewModel.isPreparing(cancelledEpisode))
        #expect(viewModel.preparedEpisode(for: cancelledEpisode) == nil)
        #expect(viewModel.failure(for: cancelledEpisode) == nil)
        #expect(viewModel.preparedEpisode(for: completedEpisode) != nil)
    }

    @Test
    func preparationFailureIsScopedToItsPodcast() async {
        let firstPodcastEpisode = Episode(
            id: "shared-guid",
            subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            podcastTitle: "First Podcast",
            title: "First Episode",
            enclosureURL: URL(string: "https://cdn.example.com/first.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/first.xml")!
        )
        let secondPodcastEpisode = Episode(
            id: "shared-guid",
            subscriptionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            podcastTitle: "Second Podcast",
            title: "Second Episode",
            enclosureURL: URL(string: "https://cdn.example.com/second.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/second.xml")!
        )
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: FailingPreparationDownloadService(),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(
                    workspaceURL: URL(fileURLWithPath: "/tmp/simple-podcast-manager-workspace", isDirectory: true)
                )
            ),
            store: InMemoryPreparedEpisodeStore(),
            downloadedEpisodeStore: InMemoryDownloadedEpisodeStore()
        )

        await viewModel.prepare([firstPodcastEpisode], settings: AppSettings())

        #expect(viewModel.failure(for: firstPodcastEpisode)?.message == "Download failed.")
        #expect(viewModel.failure(for: secondPodcastEpisode) == nil)
    }

    private func makeEpisode(id: String, subscriptionID: UUID) -> Episode {
        Episode(
            id: id,
            subscriptionID: subscriptionID,
            podcastTitle: "Podcast \(id)",
            title: "Episode \(id)",
            enclosureURL: URL(string: "https://cdn.example.com/\(id).mp3")!,
            sourceFeedURL: URL(string: "https://example.com/\(id).xml")!
        )
    }

    private func makeDownloadedRecord(episode: Episode) -> DownloadedEpisodeRecord {
        DownloadedEpisodeRecord(
            subscriptionID: episode.subscriptionID!,
            episodeID: episode.id,
            episodeTitle: episode.title,
            preparationAction: .passthroughMP3,
            downloadedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeViewModel(
        workspaceURL: URL,
        preparedStore: InMemoryPreparedEpisodeStore,
        downloadedStore: InMemoryDownloadedEpisodeStore
    ) -> PreparationPreviewViewModel {
        PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: StubPreparationDownloadService(),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: workspaceURL)
            ),
            store: preparedStore,
            downloadedEpisodeStore: downloadedStore
        )
    }
}

private struct StubPreparationDownloadService: DownloadService {
    func download(_ episode: Episode, into workspaceURL: URL, allowsInsecureHTTP: Bool) async throws -> URL {
        workspaceURL.appendingPathComponent("\(episode.id).mp3")
    }
}

private struct FailingPreparationDownloadService: DownloadService {
    func download(_ episode: Episode, into workspaceURL: URL, allowsInsecureHTTP: Bool) async throws -> URL {
        throw TestPreparationError.downloadFailed
    }
}

private enum TestPreparationError: LocalizedError {
    case downloadFailed

    var errorDescription: String? {
        "Download failed."
    }
}

private struct FailingPreparedMediaFileDeleter: PreparedMediaFileDeleting {
    func fileExists(at url: URL) -> Bool {
        true
    }

    func removeItem(at url: URL) throws {
        throw TestPreparationError.downloadFailed
    }
}

private struct DelayedPreparationDownloadService: DownloadService {
    func download(_ episode: Episode, into workspaceURL: URL, allowsInsecureHTTP: Bool) async throws -> URL {
        try await Task.sleep(nanoseconds: 10_000_000)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let fileURL = workspaceURL.appendingPathComponent("\(episode.id).mp3")
        try Data("audio".utf8).write(to: fileURL)
        return fileURL
    }
}

private struct CancellablePreparationDownloadService: DownloadService {
    let cancelledEpisodeID: String

    func download(
        _ episode: Episode,
        into workspaceURL: URL,
        allowsInsecureHTTP: Bool
    ) async throws -> URL {
        if episode.id == cancelledEpisodeID {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let fileURL = workspaceURL.appendingPathComponent("\(episode.id).mp3")
        try Data("audio".utf8).write(to: fileURL)
        return fileURL
    }
}

private actor PreparationDownloadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasStarted = false

    func waitForPermission() async {
        hasStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func allowDownload() {
        continuation?.resume()
        continuation = nil
    }
}

private struct SuspendedPreparationDownloadService: DownloadService {
    let gate: PreparationDownloadGate

    func download(_ episode: Episode, into workspaceURL: URL, allowsInsecureHTTP: Bool) async throws -> URL {
        await gate.waitForPermission()
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let fileURL = workspaceURL.appendingPathComponent("\(episode.id).mp3")
        try Data("audio".utf8).write(to: fileURL)
        return fileURL
    }
}

private struct StubPreparationAudioConversionService: AudioConversionService {
    func prepareAudio(for episode: Episode, sourceFileURL: URL, in workspaceURL: URL, settings: AppSettings) async throws -> PreparedEpisode {
        PreparedEpisode(
            episode: episode,
            sourceFileURL: sourceFileURL,
            preparedFileURL: sourceFileURL,
            preparationAction: .passthroughMP3
        )
    }
}

private struct StubPreparationWorkspaceProvider: MediaWorkspaceProviding {
    let workspaceURL: URL

    func makeWorkspace() throws -> URL {
        workspaceURL
    }
}

private final class InMemoryPreparedEpisodeStore: PreparedEpisodeStore, @unchecked Sendable {
    var preparedEpisodes: [PreparedEpisode]

    init(preparedEpisodes: [PreparedEpisode] = []) {
        self.preparedEpisodes = preparedEpisodes
    }

    func loadPreparedEpisodes() throws -> [PreparedEpisode] {
        preparedEpisodes
    }

    func savePreparedEpisodes(_ preparedEpisodes: [PreparedEpisode]) throws {
        self.preparedEpisodes = preparedEpisodes
    }
}

private final class InMemoryDownloadedEpisodeStore: DownloadedEpisodeStore, @unchecked Sendable {
    var downloadedEpisodes: [DownloadedEpisodeRecord]

    init(downloadedEpisodes: [DownloadedEpisodeRecord] = []) {
        self.downloadedEpisodes = downloadedEpisodes
    }

    func loadDownloadedEpisodes() throws -> [DownloadedEpisodeRecord] {
        downloadedEpisodes
    }

    func saveDownloadedEpisodes(_ downloadedEpisodes: [DownloadedEpisodeRecord]) throws {
        self.downloadedEpisodes = downloadedEpisodes
    }
}
