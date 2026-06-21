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
        #expect(viewModel.workspaceURL == workspaceURL)
        #expect(viewModel.failures.isEmpty)
        #expect(viewModel.progress == nil)
        #expect(store.preparedEpisodes.count == 1)
        #expect(downloadedStore.downloadedEpisodes.count == 1)
        #expect(downloadedStore.downloadedEpisodes.first?.episodeID == "ep-1")
    }

    @Test
    func loadsPersistedPreparedEpisodesOnLaunch() throws {
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

        viewModel.loadPersistedPreparedEpisodes()

        #expect(viewModel.hasLoadedPreparedEpisodes)
        #expect(viewModel.preparedEpisodes == [preparedEpisode])
    }

    @Test
    func loadsPersistedDownloadedEpisodeHistory() throws {
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

        viewModel.loadPersistedPreparedEpisodes()

        #expect(viewModel.downloadedRecord(for: episode) == downloadedRecord)
    }

    @Test
    func removeAllPreparedEpisodesDeletesLocalFilesAndPersistsEmptyState() throws {
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
        viewModel.loadPersistedPreparedEpisodes()

        viewModel.removeAllPreparedEpisodes()

        #expect(viewModel.preparedEpisodes.isEmpty)
        #expect(!viewModel.downloadedEpisodes.isEmpty)
        #expect(store.preparedEpisodes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(!FileManager.default.fileExists(atPath: preparedURL.path))
    }

    @Test
    func tracksActiveDownloadsWhilePreparingMultipleEpisodes() async throws {
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

        #expect(viewModel.activeDownloads.count == 2)
        #expect(viewModel.isPreparing(episodes[0]))
        #expect(viewModel.isPreparing(episodes[1]))

        await preparationTask.value

        #expect(viewModel.activeDownloads.isEmpty)
        #expect(!viewModel.isPreparing)
        #expect(viewModel.preparedEpisodes.count == 2)
    }
}

private struct StubPreparationDownloadService: DownloadService {
    func download(_ episode: Episode, into workspaceURL: URL) async throws -> URL {
        workspaceURL.appendingPathComponent("\(episode.id).mp3")
    }
}

private struct DelayedPreparationDownloadService: DownloadService {
    func download(_ episode: Episode, into workspaceURL: URL) async throws -> URL {
        try await Task.sleep(nanoseconds: 10_000_000)
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

private struct StubPreparationWorkspaceProvider: TemporaryWorkspaceProviding {
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
