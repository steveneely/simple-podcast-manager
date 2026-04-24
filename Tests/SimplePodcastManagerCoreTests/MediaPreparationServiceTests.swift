import Foundation
import Testing
@testable import SimplePodcastManagerCore

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

    @Test
    func convertsNonMp3EpisodesWithBundledFfmpegWhenPathBlank() async throws {
        let episode = Episode(
            id: "ep-wav",
            podcastTitle: "Example Podcast",
            title: "Episode WAV",
            enclosureURL: URL(string: "https://cdn.example.com/episode.wav")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let bundledURL = URL(fileURLWithPath: "/Applications/Simple Podcast Manager.app/Contents/Resources/ffmpeg")
        let commandRunner = CapturingCommandRunner(
            result: CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: "")
        )
        let service = MediaPreparationService(
            downloadService: StubDownloadService(fileExtension: "wav"),
            audioConversionService: FFmpegAudioConversionService(
                commandRunner: commandRunner,
                bundledExecutableURL: bundledURL
            ),
            workspaceProvider: StubWorkspaceProvider()
        )

        let result = try await service.prepareEpisodes([episode], settings: AppSettings())

        #expect(result.preparedEpisodes.count == 1)
        #expect(result.preparedEpisodes.first?.preparationAction == .convertedToMP3)
        #expect(commandRunner.executableURLs == [bundledURL])
    }

    @Test
    func reportsPreparationProgressAcrossEpisodes() async throws {
        let firstEpisode = Episode(
            id: "ep-1",
            podcastTitle: "Example Podcast",
            title: "Episode 1",
            enclosureURL: URL(string: "https://cdn.example.com/episode1.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let secondEpisode = Episode(
            id: "ep-2",
            podcastTitle: "Example Podcast",
            title: "Episode 2",
            enclosureURL: URL(string: "https://cdn.example.com/episode2.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let service = MediaPreparationService(
            downloadService: StubDownloadService(fileExtension: "mp3"),
            audioConversionService: StubAudioConversionService(),
            workspaceProvider: StubWorkspaceProvider()
        )

        let collector = ProgressCollector()
        _ = try await service.prepareEpisodes(
            [firstEpisode, secondEpisode],
            settings: AppSettings(),
            progress: { collector.append($0) }
        )
        let progressUpdates = collector.values

        #expect(progressUpdates.count == 3)
        #expect(progressUpdates[0] == PreparationProgress(totalCount: 2, completedCount: 0, currentEpisodeID: "ep-1", currentEpisodeTitle: "Episode 1"))
        #expect(progressUpdates[1] == PreparationProgress(totalCount: 2, completedCount: 1, currentEpisodeID: "ep-2", currentEpisodeTitle: "Episode 2"))
        #expect(progressUpdates[2] == PreparationProgress(totalCount: 2, completedCount: 2))
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

private final class CapturingCommandRunner: CommandRunning, @unchecked Sendable {
    private let result: CommandRunResult
    private var capturedExecutableURLs: [URL] = []

    init(result: CommandRunResult) {
        self.result = result
    }

    func run(executableURL: URL, arguments: [String]) async throws -> CommandRunResult {
        capturedExecutableURLs.append(executableURL)
        return result
    }

    var executableURLs: [URL] {
        capturedExecutableURLs
    }
}

private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var progressUpdates: [PreparationProgress] = []

    func append(_ progress: PreparationProgress) {
        lock.lock()
        defer { lock.unlock() }
        progressUpdates.append(progress)
    }

    var values: [PreparationProgress] {
        lock.lock()
        defer { lock.unlock() }
        return progressUpdates
    }
}
