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

        let result = await service.prepareEpisode(episode, settings: AppSettings())

        guard case .prepared(let prepared) = result else { Issue.record("Expected prepared audio"); return }
        #expect(prepared.preparationAction == .passthroughMP3)
        #expect(prepared.preparedAt.timeIntervalSince1970 > 0)
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
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        let service = MediaPreparationService(
            downloadService: StubDownloadService(fileExtension: "m4a"),
            audioConversionService: FFmpegAudioConversionService(commandRunner: StubCommandRunner(result: .success(CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: "")))),
            workspaceProvider: FixedWorkspaceProvider(workspaceURL: workspaceURL)
        )

        let result = await service.prepareEpisode(episode, settings: AppSettings())

        guard case .failed(let failure) = result else { Issue.record("Expected conversion failure"); return }
        #expect(failure.message == AudioConversionError.ffmpegNotConfigured.localizedDescription)
        #expect(!FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("ep-m4a.m4a").path))
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
            audioConversionService: FFmpegAudioConversionService(
                commandRunner: StubCommandRunner(result: .success(CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: ""))),
                metadataTaggingService: CapturingMP3MetadataTaggingService()
            ),
            workspaceProvider: StubWorkspaceProvider()
        )

        let result = await service.prepareEpisode(
            episode,
            settings: AppSettings(ffmpegExecutablePath: "/opt/homebrew/bin/ffmpeg")
        )

        guard case .prepared(let prepared) = result else { Issue.record("Expected prepared audio"); return }
        #expect(prepared.preparationAction == .convertedToMP3)
        #expect(prepared.preparedFileURL.pathExtension == "mp3")
    }

    @Test
    func normalizesMp3MetadataAndIncludesArtworkWithoutFfmpeg() async throws {
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
        let taggingService = CapturingMP3MetadataTaggingService()
        let service = FFmpegAudioConversionService(
            commandRunner: commandRunner,
            artworkPreparationService: StubArtworkPreparationService(artworkFileURL: artworkFileURL),
            metadataTaggingService: taggingService
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
            MP3MetadataTaggingCall(
                sourceFileURL: sourceFileURL,
                episodeTitle: episode.title,
                podcastTitle: episode.podcastTitle,
                genre: AppSettings.defaultMP3Genre,
                artworkFileURL: artworkFileURL,
                destinationFileURL: preparedEpisode.preparedFileURL
            ),
        ])
    }

    @Test
    func normalizesMp3MetadataWhenArtworkIsUnavailable() async throws {
        let episode = Episode(
            id: "ep-mp3-no-art",
            podcastTitle: "Example Podcast",
            title: "Episode MP3 Without Art",
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let workspaceURL = try StubWorkspaceProvider().makeWorkspace()
        let sourceFileURL = workspaceURL.appending(path: "episode.mp3")
        try Data("audio".utf8).write(to: sourceFileURL)
        let taggingService = CapturingMP3MetadataTaggingService()
        let service = FFmpegAudioConversionService(
            metadataTaggingService: taggingService
        )

        let preparedEpisode = try await service.prepareAudio(
            for: episode,
            sourceFileURL: sourceFileURL,
            in: workspaceURL,
            settings: AppSettings()
        )

        #expect(preparedEpisode.preparedFileURL != sourceFileURL)
        #expect(preparedEpisode.preparationWarnings == nil)
        #expect(taggingService.calls.first?.episodeTitle == episode.title)
        #expect(taggingService.calls.first?.podcastTitle == episode.podcastTitle)
        #expect(taggingService.calls.first?.genre == AppSettings.defaultMP3Genre)
        #expect(taggingService.calls.first?.artworkFileURL == nil)
    }

    @Test
    func prefixesMetadataTitleWithPublicationDateWhenEnabled() async throws {
        let publicationDate = try #require(ISO8601DateFormatter().date(from: "2026-08-11T12:00:00Z"))
        let episode = Episode(
            id: "ep-mp3-date-prefix",
            podcastTitle: "Example Podcast",
            title: "Original Title",
            publicationDate: publicationDate,
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let workspaceURL = try StubWorkspaceProvider().makeWorkspace()
        let sourceFileURL = workspaceURL.appending(path: "episode.mp3")
        try Data("audio".utf8).write(to: sourceFileURL)
        let taggingService = CapturingMP3MetadataTaggingService()
        let service = FFmpegAudioConversionService(
            metadataTaggingService: taggingService
        )

        _ = try await service.prepareAudio(
            for: episode,
            sourceFileURL: sourceFileURL,
            in: workspaceURL,
            settings: AppSettings(prefixesPublicationDateInEpisodeTitles: true)
        )

        #expect(taggingService.calls.first?.episodeTitle == "08.11 Original Title")
        #expect(taggingService.calls.first?.podcastTitle == episode.podcastTitle)
    }

    @Test
    func writesConfiguredGenreToMetadata() async throws {
        let episode = Episode(
            id: "ep-mp3-genre",
            podcastTitle: "Example Podcast",
            title: "Original Title",
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let workspaceURL = try StubWorkspaceProvider().makeWorkspace()
        let sourceFileURL = workspaceURL.appending(path: "episode.mp3")
        try Data("audio".utf8).write(to: sourceFileURL)
        let taggingService = CapturingMP3MetadataTaggingService()
        let service = FFmpegAudioConversionService(
            metadataTaggingService: taggingService
        )

        _ = try await service.prepareAudio(
            for: episode,
            sourceFileURL: sourceFileURL,
            in: workspaceURL,
            settings: AppSettings(mp3Genre: "Spoken Word")
        )

        #expect(taggingService.calls.first?.genre == "Spoken Word")
    }

    @Test
    func failsPreparationWhenMetadataCannotBeWritten() async throws {
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
            metadataTaggingService: FailingMP3MetadataTaggingService()
        )

        do {
            _ = try await service.prepareAudio(
                for: episode,
                sourceFileURL: sourceFileURL,
                in: workspaceURL,
                settings: AppSettings()
            )
            Issue.record("Expected metadata tagging to fail")
        } catch let error as AudioConversionError {
            guard case .metadataWritingFailed = error else {
                Issue.record("Expected metadataWritingFailed, got \(error)")
                return
            }
        }
        #expect(commandRunner.arguments.isEmpty)
    }

    @Test
    func writesMetadataWithoutArtworkWhenArtworkCannotBePrepared() async throws {
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
        let taggingService = CapturingMP3MetadataTaggingService()
        let service = FFmpegAudioConversionService(
            commandRunner: commandRunner,
            artworkPreparationService: FailingArtworkPreparationService(),
            metadataTaggingService: taggingService
        )

        let preparedEpisode = try await service.prepareAudio(
            for: episode,
            sourceFileURL: sourceFileURL,
            in: workspaceURL,
            settings: AppSettings()
        )

        #expect(preparedEpisode.preparedFileURL != sourceFileURL)
        #expect(preparedEpisode.preparationWarnings == ["Cover art was not added because the artwork could not be downloaded or read."])
        #expect(taggingService.calls.first?.artworkFileURL == nil)
        #expect(commandRunner.arguments.isEmpty)
    }

    @Test
    func insecureDownloadChoiceAlsoAppliesToEpisodeArtwork() async throws {
        let artworkURL = URL(string: "http://images.example.com/artwork.jpg")!
        let episode = Episode(
            id: "ep-http-art",
            podcastTitle: "Example Podcast",
            title: "Episode With HTTP Artwork",
            artworkURL: artworkURL,
            enclosureURL: URL(string: "https://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let workspaceURL = try StubWorkspaceProvider().makeWorkspace()
        let sourceFileURL = workspaceURL.appending(path: "episode.mp3")
        let artworkFileURL = workspaceURL.appending(path: "cover.jpg")
        try Data("audio".utf8).write(to: sourceFileURL)
        try Data("artwork".utf8).write(to: artworkFileURL)
        let service = FFmpegAudioConversionService(
            artworkPreparationService: PermissionSensitiveArtworkPreparationService(
                artworkFileURL: artworkFileURL
            ),
            metadataTaggingService: CapturingMP3MetadataTaggingService()
        )

        await #expect(throws: HTTPDataResourceLoadingError.insecureDownloadRequiresPermission) {
            try await service.prepareAudio(
                for: episode,
                sourceFileURL: sourceFileURL,
                in: workspaceURL,
                settings: AppSettings()
            )
        }

        let preparedEpisode = try await service.prepareAudio(
            for: episode,
            sourceFileURL: sourceFileURL,
            in: workspaceURL,
            settings: AppSettings(allowsInsecureDownloads: true)
        )
        #expect(preparedEpisode.preparationWarnings == nil)
    }

    @Test
    func convertsAudioThenWritesMetadataAndArtworkOnce() async throws {
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
        let taggingService = CapturingMP3MetadataTaggingService()
        let service = FFmpegAudioConversionService(
            commandRunner: commandRunner,
            artworkPreparationService: StubArtworkPreparationService(artworkFileURL: artworkFileURL),
            metadataTaggingService: taggingService
        )

        let preparedEpisode = try await service.prepareAudio(
            for: episode,
            sourceFileURL: sourceFileURL,
            in: workspaceURL,
            settings: AppSettings(ffmpegExecutablePath: "/opt/homebrew/bin/ffmpeg")
        )

        #expect(preparedEpisode.preparationAction == .convertedToMP3)
        #expect(preparedEpisode.preparationWarnings == nil)
        #expect(commandRunner.executableURLs == [URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")])
        #expect(commandRunner.arguments.count == 1)
        #expect(commandRunner.arguments.first == [
            "-y",
            "-i", sourceFileURL.path,
            taggingService.calls[0].sourceFileURL.path,
        ])
        #expect(taggingService.calls[0].episodeTitle == episode.title)
        #expect(taggingService.calls[0].podcastTitle == episode.podcastTitle)
        #expect(taggingService.calls[0].artworkFileURL == artworkFileURL)
        #expect(taggingService.calls[0].destinationFileURL == preparedEpisode.preparedFileURL)
        #expect(!FileManager.default.fileExists(atPath: taggingService.calls[0].sourceFileURL.path))
    }

    @Test
    func reportsPermissionRequirementAndForwardsSavedInsecureDownloadChoice() async throws {
        let episode = Episode(
            id: "http-episode",
            podcastTitle: "Example Podcast",
            title: "HTTP Episode",
            enclosureURL: URL(string: "http://cdn.example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let service = MediaPreparationService(
            downloadService: PolicySensitiveDownloadService(),
            audioConversionService: StubAudioConversionService(),
            workspaceProvider: StubWorkspaceProvider()
        )

        let blockedResult = await service.prepareEpisode(episode, settings: AppSettings())
        let allowedResult = await service.prepareEpisode(
            episode,
            settings: AppSettings(allowsInsecureDownloads: true)
        )

        guard case .failed(let failure) = blockedResult else { Issue.record("Expected permission request"); return }
        #expect(failure.reason == .insecureDownloadRequiresPermission)
        guard case .prepared = allowedResult else { Issue.record("Expected approved download"); return }
    }
}

private struct PolicySensitiveDownloadService: DownloadService {
    func download(_ episode: Episode, into workspaceURL: URL, allowsInsecureHTTP: Bool) async throws -> URL {
        guard allowsInsecureHTTP else {
            throw DownloadServiceError.insecureDownloadRequiresPermission
        }

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let fileURL = workspaceURL.appendingPathComponent("\(episode.id).mp3")
        try Data("audio".utf8).write(to: fileURL)
        return fileURL
    }
}

private struct StubDownloadService: DownloadService {
    let fileExtension: String

    func download(_ episode: Episode, into workspaceURL: URL, allowsInsecureHTTP: Bool) async throws -> URL {
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

private struct StubWorkspaceProvider: MediaWorkspaceProviding {
    func makeWorkspace() throws -> URL {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        return workspaceURL
    }
}

private struct FixedWorkspaceProvider: MediaWorkspaceProviding {
    let workspaceURL: URL

    func makeWorkspace() throws -> URL {
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
        if result.terminationStatus == 0, let outputPath = arguments.last {
            try Data("converted audio".utf8).write(to: URL(fileURLWithPath: outputPath))
        }
        return result
    }

    var executableURLs: [URL] {
        capturedExecutableURLs
    }

    var arguments: [[String]] {
        capturedArguments
    }
}

private struct MP3MetadataTaggingCall: Equatable {
    var sourceFileURL: URL
    var episodeTitle: String
    var podcastTitle: String
    var genre: String
    var artworkFileURL: URL?
    var destinationFileURL: URL
}

private final class CapturingMP3MetadataTaggingService: MP3MetadataTaggingService, @unchecked Sendable {
    private(set) var calls: [MP3MetadataTaggingCall] = []

    func writeMetadata(
        sourceFileURL: URL,
        episodeTitle: String,
        podcastTitle: String,
        genre: String,
        artworkFileURL: URL?,
        destinationFileURL: URL
    ) throws {
        calls.append(
            MP3MetadataTaggingCall(
                sourceFileURL: sourceFileURL,
                episodeTitle: episodeTitle,
                podcastTitle: podcastTitle,
                genre: genre,
                artworkFileURL: artworkFileURL,
                destinationFileURL: destinationFileURL
            )
        )
        try FileManager.default.createDirectory(
            at: destinationFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("tagged".utf8).write(to: destinationFileURL)
    }
}

private struct FailingMP3MetadataTaggingService: MP3MetadataTaggingService {
    func writeMetadata(
        sourceFileURL: URL,
        episodeTitle: String,
        podcastTitle: String,
        genre: String,
        artworkFileURL: URL?,
        destinationFileURL: URL
    ) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

private struct StubArtworkPreparationService: ArtworkPreparationService {
    let artworkFileURL: URL

    func prepareArtwork(from artworkURL: URL, in workspaceURL: URL, allowsInsecureHTTP: Bool) async throws -> URL {
        artworkFileURL
    }
}

private struct FailingArtworkPreparationService: ArtworkPreparationService {
    func prepareArtwork(from artworkURL: URL, in workspaceURL: URL, allowsInsecureHTTP: Bool) async throws -> URL {
        throw ArtworkPreparationError.invalidImage
    }
}

private struct PermissionSensitiveArtworkPreparationService: ArtworkPreparationService {
    let artworkFileURL: URL

    func prepareArtwork(from artworkURL: URL, in workspaceURL: URL, allowsInsecureHTTP: Bool) async throws -> URL {
        guard allowsInsecureHTTP else {
            throw HTTPDataResourceLoadingError.insecureDownloadRequiresPermission
        }
        return artworkFileURL
    }
}
