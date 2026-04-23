import Foundation
import Testing
@testable import PodcastSwiftCore

struct MediaPreparationServiceTests {
    @Test
    func preparesMp3EpisodesWithoutConversion() async throws {
        let episode = Episode(
            id: "ep-mp3",
            podcastTitle: "Example Podcast",
            title: "Episode MP3",
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let service = MediaPreparationService(
            downloadService: StubDownloadService(fileExtension: "mp3"),
            audioConversionService: StubAudioConversionService(),
            workspaceProvider: StubWorkspaceProvider()
        )

        let result = try await service.prepareEpisodes([episode], settings: AppSettings())

        #expect(result.preparedEpisodes.count == 1)
        #expect(result.preparedEpisodes.first?.preparationAction == .passthroughMP3)
        #expect(result.failures.isEmpty)
    }

    @Test
    func recordsConversionFailureForNonMp3WithoutFfmpeg() async throws {
        let episode = Episode(
            id: "ep-m4a",
            podcastTitle: "Example Podcast",
            title: "Episode M4A",
            enclosureURL: URL(string: "https://cdn.example.com/episode.m4a")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let service = MediaPreparationService(
            downloadService: StubDownloadService(fileExtension: "m4a"),
            audioConversionService: FFmpegAudioConversionService(commandRunner: StubCommandRunner(result: .success(CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: "")))),
            workspaceProvider: StubWorkspaceProvider()
        )

        let result = try await service.prepareEpisodes([episode], settings: AppSettings())

        #expect(result.preparedEpisodes.isEmpty)
        #expect(result.failures.count == 1)
    }

    @Test
    func convertsNonMp3EpisodesWhenFfmpegConfigured() async throws {
        let episode = Episode(
            id: "ep-aac",
            podcastTitle: "Example Podcast",
            title: "Episode AAC",
            enclosureURL: URL(string: "https://cdn.example.com/episode.aac")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let service = MediaPreparationService(
            downloadService: StubDownloadService(fileExtension: "aac"),
            audioConversionService: FFmpegAudioConversionService(commandRunner: StubCommandRunner(result: .success(CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: "")))),
            workspaceProvider: StubWorkspaceProvider()
        )

        let result = try await service.prepareEpisodes(
            [episode],
            settings: AppSettings(ffmpegExecutablePath: "/opt/homebrew/bin/ffmpeg")
        )

        #expect(result.preparedEpisodes.count == 1)
        #expect(result.preparedEpisodes.first?.preparationAction == .convertedToMP3)
        #expect(result.preparedEpisodes.first?.preparedFileURL.pathExtension == "mp3")
    }
}

private struct StubDownloadService: DownloadService {
    let fileExtension: String

    func download(_ episode: Episode, into workspaceURL: URL) async throws -> URL {
        let fileURL = workspaceURL.appendingPathComponent("\(episode.id).\(fileExtension)")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: fileURL)
        return fileURL
    }
}

private struct StubAudioConversionService: AudioConversionService {
    func prepareAudio(for episode: Episode, sourceFileURL: URL, in workspaceURL: URL, settings: AppSettings) async throws -> PreparedEpisode {
        PreparedEpisode(
            episode: episode,
            sourceFileURL: sourceFileURL,
            preparedFileURL: sourceFileURL,
            preparationAction: .passthroughMP3
        )
    }
}

private struct StubWorkspaceProvider: TemporaryWorkspaceProviding {
    func makeWorkspace() throws -> URL {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        return workspaceURL
    }
}

private struct StubCommandRunner: CommandRunning {
    let result: Result<CommandRunResult, Error>

    func run(executableURL: URL, arguments: [String]) async throws -> CommandRunResult {
        try result.get()
    }
}
