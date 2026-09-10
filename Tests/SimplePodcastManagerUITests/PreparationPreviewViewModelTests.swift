import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct PreparationPreviewViewModelTests {
    @Test
    func retainedEpisodeCanBeRemovedAndHistoryDoesNotKeepItsRowVisible() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let file = workspace.appendingPathComponent("saved.mp3")
        try Data("audio".utf8).write(to: file)
        let podcastID = UUID()
        let episode = Episode(id: "saved", subscriptionID: podcastID, podcastTitle: "Test", title: "Saved episode",
                              enclosureURL: URL(string: "https://example.com/saved.mp3")!, sourceFeedURL: URL(string: "https://example.com/rss")!)
        let prepared = PreparedEpisode(episode: episode, sourceFileURL: file, preparedFileURL: file, preparationAction: .passthroughMP3)
        let store = InMemoryPreparedEpisodeStore(preparedEpisodes: [prepared])
        let history = DownloadedEpisodeRecord(subscriptionID: podcastID, episodeID: episode.id, episodeTitle: episode.title, preparationAction: .passthroughMP3, downloadedAt: Date(timeIntervalSince1970: 0))
        let downloadedStore = InMemoryDownloadedEpisodeStore(downloadedEpisodes: [history])
        let preparation = PreparationPreviewViewModel(
            service: MediaPreparationService(downloadService: StubPreparationDownloadService(), audioConversionService: StubPreparationAudioConversionService(), workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: workspace)),
            store: store, downloadedEpisodeStore: downloadedStore
        )
        try await preparation.applyPersistedState(preparedEpisodes: [prepared], downloadedEpisodes: [history])
        let preview = PodcastPreviewViewModel()
        let rows = preview.episodesIncludingDownloads(for: podcastID, preparedEpisodes: preparation.preparedEpisodes)
        #expect(rows == [episode])
        #expect(preparation.preparedEpisode(for: rows[0]) != nil)
        await preparation.removePreparedEpisode(for: rows[0])
        #expect(preparation.lastErrorMessage == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(store.preparedEpisodes.isEmpty)
        #expect(preparation.downloadedRecord(for: episode) == history)
        #expect(preview.episodesIncludingDownloads(for: podcastID, preparedEpisodes: preparation.preparedEpisodes).isEmpty)
    }

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

        try await viewModel.applyPersistedState(preparedEpisodes: store.preparedEpisodes, downloadedEpisodes: [])

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

        try await viewModel.applyPersistedState(preparedEpisodes: [], downloadedEpisodes: [downloadedRecord])

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
        try await viewModel.applyPersistedState(preparedEpisodes: store.preparedEpisodes, downloadedEpisodes: downloadedStore.downloadedEpisodes)

        await viewModel.removePreparedEpisodes(viewModel.preparedEpisodes)

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
        try await viewModel.applyPersistedState(preparedEpisodes: preparedStore.preparedEpisodes, downloadedEpisodes: downloadedStore.downloadedEpisodes)

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
        try await viewModel.applyPersistedState(preparedEpisodes: preparedStore.preparedEpisodes, downloadedEpisodes: downloadedStore.downloadedEpisodes)

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
        try await viewModel.applyPersistedState(preparedEpisodes: store.preparedEpisodes, downloadedEpisodes: [])

        await viewModel.removePreparedEpisodes(viewModel.preparedEpisodes)

        #expect(viewModel.preparedEpisodes == [preparedEpisode])
        #expect(store.preparedEpisodes == [preparedEpisode])
        #expect(viewModel.lastErrorMessage?.contains("Could not delete the downloaded files for \"Episode 1\"") == true)
    }

    @Test
    func tracksPreparingStateForEachEpisode() async throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let startObserver = PreparationStartObserver()
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: ObservingPreparationDownloadService(observer: startObserver),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: workspaceURL)
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

        startObserver.onStart = { _ in
            #expect(viewModel.preparingEpisodeCount == 2)
            #expect(viewModel.isPreparing(episodes[0]))
            #expect(viewModel.isPreparing(episodes[1]))
        }

        await viewModel.prepare(episodes, settings: AppSettings())

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

        let startObserver = PreparationStartObserver()
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: ObservingPreparationDownloadService(observer: startObserver),
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

        startObserver.onStart = { _ in
            #expect(viewModel.isPreparing(firstPodcastEpisode))
            #expect(!viewModel.isPreparing(secondPodcastEpisode))
        }

        await viewModel.prepare([firstPodcastEpisode], settings: AppSettings())

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

        let startObserver = PreparationStartObserver()
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: CancellablePreparationDownloadService(
                    cancelledEpisodeID: "cancel-me",
                    observer: startObserver
                ),
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

        startObserver.onStart = { episode in
            if episode.id == cancelledEpisode.id {
                viewModel.cancelPreparation(for: cancelledEpisode)
            }
        }

        await viewModel.prepare([cancelledEpisode, completedEpisode], settings: AppSettings())

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

    @Test(.timeLimit(.minutes(1)))
    func queueSharesItsLimitAcrossRequestsAndPublishesCompletionBeforeSlowDownloads() async throws {
        let gate = GatedPreparationDownloadService()
        let preparedStore = InMemoryPreparedEpisodeStore()
        let downloadedStore = InMemoryDownloadedEpisodeStore()
        let model = PreparationPreviewViewModel(
            service: MediaPreparationService(downloadService: gate, audioConversionService: StubPreparationAudioConversionService(), workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: FileManager.default.temporaryDirectory)),
            store: preparedStore, downloadedEpisodeStore: downloadedStore
        )
        let episodes = (1...5).map { makeEpisode(id: "queue-\($0)", subscriptionID: UUID()) }
        let first = Task { await model.prepare(Array(episodes.prefix(3)), settings: AppSettings()) }
        await gate.waitForStarts(3)
        let second = Task { await model.prepare(Array(episodes.suffix(2)), settings: AppSettings()) }
        while model.preparingEpisodeCount != 5 { await Task.yield() }
        #expect(gate.startedIDs.count == 3)

        gate.finish(episodes[1].id)
        await gate.waitForStarts(4)
        #expect(model.preparedEpisode(for: episodes[1]) != nil)
        #expect(model.downloadedRecord(for: episodes[1]) != nil)
        #expect(preparedStore.preparedEpisodes.map(\.episode.id) == [episodes[1].id])
        #expect(downloadedStore.downloadedEpisodes.map(\.episodeID) == [episodes[1].id])
        #expect(model.isPreparing(episodes[0]))
        #expect(!model.isPreparing(episodes[1]))

        gate.finish(episodes[0].id)
        await gate.waitForStarts(5)
        for episode in [episodes[2], episodes[3], episodes[4]] { gate.finish(episode.id) }
        await first.value
        await second.value
        #expect(gate.maximumActiveCount == 3)
        #expect(model.preparedEpisodes.count == 5)
        #expect(!model.isPreparing)
    }

    @Test(.timeLimit(.minutes(1)))
    func queuedCancellationNeverStartsAndDuplicateRequestsShareOneDownload() async {
        let gate = GatedPreparationDownloadService()
        let model = PreparationPreviewViewModel(
            service: MediaPreparationService(downloadService: gate, audioConversionService: StubPreparationAudioConversionService(), workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: FileManager.default.temporaryDirectory)),
            store: InMemoryPreparedEpisodeStore(), downloadedEpisodeStore: InMemoryDownloadedEpisodeStore()
        )
        let episodes = (1...4).map { makeEpisode(id: "cancel-queue-\($0)", subscriptionID: UUID()) }
        let first = Task { await model.prepare(episodes, settings: AppSettings()) }
        await gate.waitForStarts(3)
        model.cancelPreparation(for: episodes[3])
        #expect(!model.isPreparing(episodes[3]))
        let duplicate = Task { await model.prepare([episodes[0], episodes[0]], settings: AppSettings()) }
        for episode in episodes.prefix(3) { gate.finish(episode.id) }
        await first.value
        await duplicate.value
        // Concurrent downloads may reach the service in any order; each must start exactly once.
        #expect(gate.startedIDs.sorted() == episodes.prefix(3).map(\.id).sorted())
        #expect(model.preparedEpisodes.count == 3)
        #expect(model.failure(for: episodes[3]) == nil)
        #expect(model.downloadedRecord(for: episodes[3]) == nil)
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

private struct CancellablePreparationDownloadService: DownloadService {
    let cancelledEpisodeID: String
    let observer: PreparationStartObserver

    func download(
        _ episode: Episode,
        into workspaceURL: URL,
        allowsInsecureHTTP: Bool
    ) async throws -> URL {
        await observer.recordStart(of: episode)
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

private struct ObservingPreparationDownloadService: DownloadService {
    let observer: PreparationStartObserver

    func download(_ episode: Episode, into workspaceURL: URL, allowsInsecureHTTP: Bool) async throws -> URL {
        await observer.recordStart(of: episode)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let fileURL = workspaceURL.appendingPathComponent("\(episode.id).mp3")
        try Data("audio".utf8).write(to: fileURL)
        return fileURL
    }
}

@MainActor
private final class PreparationStartObserver: Sendable {
    var onStart: ((Episode) -> Void)?

    func recordStart(of episode: Episode) {
        onStart?(episode)
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

@MainActor
private final class GatedPreparationDownloadService: DownloadService {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var pending: [String: CheckedContinuation<URL, any Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var startedIDs: [String] = []
    private(set) var maximumActiveCount = 0

    func download(_ episode: Episode, into workspaceURL: URL, allowsInsecureHTTP: Bool) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[episode.id] = continuation
                startedIDs.append(episode.id)
                maximumActiveCount = max(maximumActiveCount, pending.count)
                let ready = waiters.filter { startedIDs.count >= $0.0 }
                waiters.removeAll { startedIDs.count >= $0.0 }
                for (_, waiter) in ready { waiter.resume() }
            }
        } onCancel: {
            Task { @MainActor in self.pending.removeValue(forKey: episode.id)?.resume(throwing: CancellationError()) }
        }
    }

    func waitForStarts(_ count: Int) async {
        if startedIDs.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func finish(_ id: String) {
        pending.removeValue(forKey: id)?.resume(returning: root.appendingPathComponent("\(id).mp3"))
    }
}
