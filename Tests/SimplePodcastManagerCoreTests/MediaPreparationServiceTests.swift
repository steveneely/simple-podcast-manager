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
        #expect(result.preparedEpisodes.first?.preparedAt.timeIntervalSince1970 ?? 0 > 0)
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
    func embedsArtworkInMp3WithoutFfmpeg() async throws {
        let artworkURL = URL(string: "https://cdn.example.com/artwork.png")!
        let episode = Episode(
            id: "ep-mp3-art",
            podcastTitle: "Example Podcast",
            title: "Episode MP3 With Art",
            artworkURL: artworkURL,
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let workspaceURL = try StubWorkspaceProvider().makeWorkspace()
        let sourceFileURL = workspaceURL.appending(path: "episode.mp3")
        let artworkFileURL = workspaceURL.appending(path: "cover.jpg")
        try Data("audio".utf8).write(to: sourceFileURL)
        try Data("artwork".utf8).write(to: artworkFileURL)
        let commandRunner = CapturingCommandRunner(
            result: CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: "")
        )
        let taggingService = CapturingMP3ArtworkTaggingService()
        let service = FFmpegAudioConversionService(
            commandRunner: commandRunner,
            artworkPreparationService: StubArtworkPreparationService(artworkFileURL: artworkFileURL),
            mp3ArtworkTaggingService: taggingService,
            bundledExecutableURL: nil
        )

        let preparedEpisode = try await service.prepareAudio(
            for: episode,
            sourceFileURL: sourceFileURL,
            in: workspaceURL,
            settings: AppSettings()
        )

        #expect(preparedEpisode.preparationAction == .passthroughMP3)
        #expect(preparedEpisode.preparationWarnings == nil)
        #expect(preparedEpisode.preparedFileURL.deletingLastPathComponent().lastPathComponent == "prepared")
        #expect(preparedEpisode.preparedFileURL.lastPathComponent == EpisodeFileName.fileName(for: episode, fileExtension: "mp3"))
        #expect(commandRunner.executableURLs.isEmpty)
        #expect(commandRunner.arguments.isEmpty)
        #expect(taggingService.calls == [
            MP3ArtworkTaggingCall(
                sourceFileURL: sourceFileURL,
                artworkFileURL: artworkFileURL,
                destinationFileURL: preparedEpisode.preparedFileURL
            ),
        ])
    }

    @Test
    func warnsWhenMp3ArtworkTaggingFails() async throws {
        let episode = Episode(
            id: "ep-mp3-art-tagging-fails",
            podcastTitle: "Example Podcast",
            title: "Episode MP3 With Art",
            artworkURL: URL(string: "https://cdn.example.com/artwork.png")!,
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let workspaceURL = try StubWorkspaceProvider().makeWorkspace()
        let sourceFileURL = workspaceURL.appending(path: "episode.mp3")
        let artworkFileURL = workspaceURL.appending(path: "cover.jpg")
        try Data("audio".utf8).write(to: sourceFileURL)
        try Data("artwork".utf8).write(to: artworkFileURL)
        let commandRunner = CapturingCommandRunner(
            result: CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: "")
        )
        let service = FFmpegAudioConversionService(
            commandRunner: commandRunner,
            artworkPreparationService: StubArtworkPreparationService(artworkFileURL: artworkFileURL),
            mp3ArtworkTaggingService: FailingMP3ArtworkTaggingService(),
            bundledExecutableURL: nil
        )

        let preparedEpisode = try await service.prepareAudio(
            for: episode,
            sourceFileURL: sourceFileURL,
            in: workspaceURL,
            settings: AppSettings()
        )

        #expect(preparedEpisode.preparedFileURL == sourceFileURL)
        #expect(preparedEpisode.preparationWarnings == ["Cover art was not added because the MP3 could not be tagged."])
        #expect(commandRunner.arguments.isEmpty)
    }

    @Test
    func returnsOriginalMp3WhenArtworkCannotBePrepared() async throws {
        let episode = Episode(
            id: "ep-mp3-art-fallback",
            podcastTitle: "Example Podcast",
            title: "Episode MP3 With Missing Art",
            artworkURL: URL(string: "https://cdn.example.com/missing.png")!,
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let workspaceURL = try StubWorkspaceProvider().makeWorkspace()
        let sourceFileURL = workspaceURL.appending(path: "episode.mp3")
        try Data("audio".utf8).write(to: sourceFileURL)
        let commandRunner = CapturingCommandRunner(
            result: CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: "")
        )
        let service = FFmpegAudioConversionService(
            commandRunner: commandRunner,
            artworkPreparationService: FailingArtworkPreparationService(),
            bundledExecutableURL: URL(fileURLWithPath: "/bin/ffmpeg")
        )

        let preparedEpisode = try await service.prepareAudio(
            for: episode,
            sourceFileURL: sourceFileURL,
            in: workspaceURL,
            settings: AppSettings()
        )

        #expect(preparedEpisode.preparedFileURL == sourceFileURL)
        #expect(preparedEpisode.preparationWarnings == ["Cover art was not added because the artwork could not be downloaded or read."])
        #expect(commandRunner.arguments.isEmpty)
    }

    @Test
    func embedsArtworkWhenConvertingNonMp3() async throws {
        let artworkURL = URL(string: "https://cdn.example.com/artwork.png")!
        let episode = Episode(
            id: "ep-aac-art",
            podcastTitle: "Example Podcast",
            title: "Episode AAC With Art",
            artworkURL: artworkURL,
            enclosureURL: URL(string: "https://cdn.example.com/episode.aac")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let workspaceURL = try StubWorkspaceProvider().makeWorkspace()
        let sourceFileURL = workspaceURL.appending(path: "episode.aac")
        let artworkFileURL = workspaceURL.appending(path: "cover.jpg")
        try Data("audio".utf8).write(to: sourceFileURL)
        try Data("artwork".utf8).write(to: artworkFileURL)
        let commandRunner = CapturingCommandRunner(
            result: CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: "")
        )
        let service = FFmpegAudioConversionService(
            commandRunner: commandRunner,
            artworkPreparationService: StubArtworkPreparationService(artworkFileURL: artworkFileURL),
            bundledExecutableURL: URL(fileURLWithPath: "/bin/ffmpeg")
        )

        let preparedEpisode = try await service.prepareAudio(
            for: episode,
            sourceFileURL: sourceFileURL,
            in: workspaceURL,
            settings: AppSettings()
        )

        #expect(preparedEpisode.preparationAction == .convertedToMP3)
        #expect(preparedEpisode.preparationWarnings == nil)
        #expect(commandRunner.arguments.first?.contains("-map") == true)
        #expect(commandRunner.arguments.first?.contains("0:a") == true)
        #expect(commandRunner.arguments.first?.contains("1:v") == true)
        #expect(commandRunner.arguments.first?.contains(artworkFileURL.path) == true)
    }

    @Test
    func retriesNonMp3ConversionWithoutArtworkWhenEmbeddingFails() async throws {
        let episode = Episode(
            id: "ep-aac-art-retry",
            podcastTitle: "Example Podcast",
            title: "Episode AAC With Art",
            artworkURL: URL(string: "https://cdn.example.com/artwork.png")!,
            enclosureURL: URL(string: "https://cdn.example.com/episode.aac")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let workspaceURL = try StubWorkspaceProvider().makeWorkspace()
        let sourceFileURL = workspaceURL.appending(path: "episode.aac")
        let artworkFileURL = workspaceURL.appending(path: "cover.jpg")
        try Data("audio".utf8).write(to: sourceFileURL)
        try Data("artwork".utf8).write(to: artworkFileURL)
        let commandRunner = SequencedCommandRunner(results: [
            CommandRunResult(terminationStatus: 1, standardOutput: "", standardError: "art failed"),
            CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: ""),
        ])
        let service = FFmpegAudioConversionService(
            commandRunner: commandRunner,
            artworkPreparationService: StubArtworkPreparationService(artworkFileURL: artworkFileURL),
            bundledExecutableURL: URL(fileURLWithPath: "/bin/ffmpeg")
        )

        let preparedEpisode = try await service.prepareAudio(
            for: episode,
            sourceFileURL: sourceFileURL,
            in: workspaceURL,
            settings: AppSettings()
        )

        #expect(preparedEpisode.preparationAction == .convertedToMP3)
        #expect(preparedEpisode.preparationWarnings == ["Cover art was not added because ffmpeg could not embed it."])
        #expect(commandRunner.arguments.count == 2)
        #expect(commandRunner.arguments[0].contains(artworkFileURL.path))
        #expect(!commandRunner.arguments[1].contains(artworkFileURL.path))
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

        #expect(progressUpdates.contains(PreparationProgress(
            totalCount: 2,
            completedCount: 0,
            currentEpisodeID: "ep-1",
            currentEpisodeTitle: "Episode 1",
            activeEpisodeIDs: ["ep-1"],
            activeEpisodeTitles: ["Episode 1"]
        )))
        #expect(progressUpdates.contains(PreparationProgress(
            totalCount: 2,
            completedCount: 0,
            currentEpisodeID: "ep-1",
            currentEpisodeTitle: "Episode 1",
            activeEpisodeIDs: ["ep-1", "ep-2"],
            activeEpisodeTitles: ["Episode 1", "Episode 2"]
        )))
        #expect(progressUpdates.last == PreparationProgress(totalCount: 2, completedCount: 2))
    }

    @Test
    func preparesEpisodesWithBoundedParallelism() async throws {
        let episodes = (1...4).map { index in
            Episode(
                id: "ep-\(index)",
                podcastTitle: "Example Podcast",
                title: "Episode \(index)",
                enclosureURL: URL(string: "https://cdn.example.com/episode\(index).mp3")!,
                sourceFeedURL: URL(string: "https://example.com/feed.xml")!
            )
        }
        let tracker = DownloadConcurrencyTracker()
        let service = MediaPreparationService(
            downloadService: DelayedDownloadService(fileExtension: "mp3", tracker: tracker),
            audioConversionService: StubAudioConversionService(),
            workspaceProvider: StubWorkspaceProvider(),
            maximumConcurrentPreparations: 2
        )

        let result = try await service.prepareEpisodes(episodes, settings: AppSettings())

        #expect(result.preparedEpisodes.count == 4)
        #expect(await tracker.maximumActiveCount == 2)
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

private struct DelayedDownloadService: DownloadService {
    let fileExtension: String
    let tracker: DownloadConcurrencyTracker

    func download(_ episode: Episode, into workspaceURL: URL) async throws -> URL {
        await tracker.start()
        try await Task.sleep(nanoseconds: 10_000_000)
        await tracker.finish()

        let fileURL = workspaceURL.appendingPathComponent("\(episode.id).\(fileExtension)")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: fileURL)
        return fileURL
    }
}

private actor DownloadConcurrencyTracker {
    private var activeCount = 0
    private var maxActiveCount = 0

    func start() {
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
    }

    func finish() {
        activeCount -= 1
    }

    var maximumActiveCount: Int {
        maxActiveCount
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
    private var capturedArguments: [[String]] = []

    init(result: CommandRunResult) {
        self.result = result
    }

    func run(executableURL: URL, arguments: [String]) async throws -> CommandRunResult {
        capturedExecutableURLs.append(executableURL)
        capturedArguments.append(arguments)
        return result
    }

    var executableURLs: [URL] {
        capturedExecutableURLs
    }

    var arguments: [[String]] {
        capturedArguments
    }
}

private final class SequencedCommandRunner: CommandRunning, @unchecked Sendable {
    private var results: [CommandRunResult]
    private(set) var arguments: [[String]] = []

    init(results: [CommandRunResult]) {
        self.results = results
    }

    func run(executableURL: URL, arguments: [String]) async throws -> CommandRunResult {
        self.arguments.append(arguments)
        return results.isEmpty
            ? CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: "")
            : results.removeFirst()
    }
}

private struct MP3ArtworkTaggingCall: Equatable {
    var sourceFileURL: URL
    var artworkFileURL: URL
    var destinationFileURL: URL
}

private final class CapturingMP3ArtworkTaggingService: MP3ArtworkTaggingService, @unchecked Sendable {
    private(set) var calls: [MP3ArtworkTaggingCall] = []

    func writeArtwork(sourceFileURL: URL, artworkFileURL: URL, destinationFileURL: URL) throws {
        calls.append(
            MP3ArtworkTaggingCall(
                sourceFileURL: sourceFileURL,
                artworkFileURL: artworkFileURL,
                destinationFileURL: destinationFileURL
            )
        )
        try Data("tagged".utf8).write(to: destinationFileURL)
    }
}

private struct FailingMP3ArtworkTaggingService: MP3ArtworkTaggingService {
    func writeArtwork(sourceFileURL: URL, artworkFileURL: URL, destinationFileURL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

private struct StubArtworkPreparationService: ArtworkPreparationService {
    let artworkFileURL: URL

    func prepareArtwork(from artworkURL: URL, in workspaceURL: URL) async throws -> URL {
        artworkFileURL
    }
}

private struct FailingArtworkPreparationService: ArtworkPreparationService {
    func prepareArtwork(from artworkURL: URL, in workspaceURL: URL) async throws -> URL {
        throw ArtworkPreparationError.invalidImage
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
