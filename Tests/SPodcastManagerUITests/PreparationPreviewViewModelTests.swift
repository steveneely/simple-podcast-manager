import Foundation
import Testing
@testable import SPodcastManagerCore
@testable import SPodcastManagerUI

@MainActor
struct PreparationPreviewViewModelTests {
    @Test
    func prepareLoadsPreparedEpisodesAndFailures() async throws {
        let workspaceURL = URL(fileURLWithPath: "/tmp/s-podcast-manager-workspace", isDirectory: true)
        let store = InMemoryPreparedEpisodeStore()
        let viewModel = PreparationPreviewViewModel(
            service: MediaPreparationService(
                downloadService: StubPreparationDownloadService(),
                audioConversionService: StubPreparationAudioConversionService(),
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: workspaceURL)
            ),
            store: store
        )
        let episode = Episode(
            id: "ep-1",
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
                workspaceProvider: StubPreparationWorkspaceProvider(workspaceURL: URL(fileURLWithPath: "/tmp/s-podcast-manager-workspace", isDirectory: true))
            ),
            store: store
        )

        viewModel.loadPersistedPreparedEpisodes()

        #expect(viewModel.hasLoadedPreparedEpisodes)
        #expect(viewModel.preparedEpisodes == [preparedEpisode])
    }
}

private struct StubPreparationDownloadService: DownloadService {
    func download(_ episode: Episode, into workspaceURL: URL) async throws -> URL {
        workspaceURL.appendingPathComponent("\(episode.id).mp3")
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
