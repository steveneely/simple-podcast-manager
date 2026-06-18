import Foundation

public struct FFmpegAudioConversionService: AudioConversionService {
    private let commandRunner: any CommandRunning
    private let artworkPreparationService: any ArtworkPreparationService
    private let mp3ArtworkTaggingService: any MP3ArtworkTaggingService
    private let bundledExecutableURL: URL?

    public init(
        commandRunner: any CommandRunning = ProcessCommandRunner(),
        artworkPreparationService: any ArtworkPreparationService = PodcastArtworkPreparationService(),
        mp3ArtworkTaggingService: any MP3ArtworkTaggingService = ID3MP3ArtworkTaggingService(),
        bundledExecutableURL: URL? = Bundle.main.url(forResource: "ffmpeg", withExtension: nil)
    ) {
        self.commandRunner = commandRunner
        self.artworkPreparationService = artworkPreparationService
        self.mp3ArtworkTaggingService = mp3ArtworkTaggingService
        self.bundledExecutableURL = bundledExecutableURL
    }

    public func prepareAudio(for episode: Episode, sourceFileURL: URL, in workspaceURL: URL, settings: AppSettings) async throws -> PreparedEpisode {
        let artworkPreparation = await preparedArtwork(for: episode, in: workspaceURL)

        if sourceFileURL.pathExtension.lowercased() == "mp3" {
            guard case .prepared(let artworkFileURL) = artworkPreparation else {
                return PreparedEpisode(
                    episode: episode,
                    sourceFileURL: sourceFileURL,
                    preparedFileURL: sourceFileURL,
                    preparationAction: .passthroughMP3,
                    preparationWarnings: artworkPreparation.warningMessage.map { [$0] }
                )
            }

            do {
                let destinationURL = try taggedMP3DestinationURL(for: episode, in: workspaceURL)
                try mp3ArtworkTaggingService.writeArtwork(
                    sourceFileURL: sourceFileURL,
                    artworkFileURL: artworkFileURL,
                    destinationFileURL: destinationURL
                )
                return PreparedEpisode(
                    episode: episode,
                    sourceFileURL: sourceFileURL,
                    preparedFileURL: destinationURL,
                    preparationAction: .passthroughMP3
                )
            } catch {
                return PreparedEpisode(
                    episode: episode,
                    sourceFileURL: sourceFileURL,
                    preparedFileURL: sourceFileURL,
                    preparationAction: .passthroughMP3,
                    preparationWarnings: [Self.failedMP3ArtworkTaggingWarning]
                )
            }

        }

        guard let executableURL = ffmpegExecutableURL(from: settings) else {
            throw AudioConversionError.ffmpegNotConfigured
        }

        let destinationURL = workspaceURL.appending(path: convertedFileName(for: episode), directoryHint: .notDirectory)
        let conversionWarnings = try await convertToMP3(
            executableURL: executableURL,
            sourceFileURL: sourceFileURL,
            artworkPreparation: artworkPreparation,
            destinationURL: destinationURL
        )

        return PreparedEpisode(
            episode: episode,
            sourceFileURL: sourceFileURL,
            preparedFileURL: destinationURL,
            preparationAction: .convertedToMP3,
            preparationWarnings: conversionWarnings.isEmpty ? nil : conversionWarnings
        )
    }

    private func ffmpegExecutableURL(from settings: AppSettings) -> URL? {
        if let ffmpegExecutablePath = settings.ffmpegExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ffmpegExecutablePath.isEmpty {
            return URL(fileURLWithPath: ffmpegExecutablePath, isDirectory: false)
        }

        return bundledExecutableURL
    }

    private func preparedArtwork(for episode: Episode, in workspaceURL: URL) async -> ArtworkPreparationOutcome {
        guard let artworkURL = episode.artworkURL else { return .notAvailable }

        do {
            return .prepared(try await artworkPreparationService.prepareArtwork(from: artworkURL, in: workspaceURL))
        } catch {
            return .failed(Self.failedArtworkPreparationWarning)
        }
    }

    private func taggedMP3DestinationURL(for episode: Episode, in workspaceURL: URL) throws -> URL {
        let directoryURL = workspaceURL.appending(path: "prepared", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appending(path: convertedFileName(for: episode), directoryHint: .notDirectory)
    }

    private func convertToMP3(
        executableURL: URL,
        sourceFileURL: URL,
        artworkPreparation: ArtworkPreparationOutcome,
        destinationURL: URL
    ) async throws -> [String] {
        switch artworkPreparation {
        case .notAvailable:
            try await runRequiredFFmpeg(
                executableURL: executableURL,
                arguments: conversionArguments(sourceFileURL: sourceFileURL, destinationURL: destinationURL)
            )
            return []
        case .failed(let warning):
            try await runRequiredFFmpeg(
                executableURL: executableURL,
                arguments: conversionArguments(sourceFileURL: sourceFileURL, destinationURL: destinationURL)
            )
            return [warning]
        case .prepared(let artworkFileURL):
            let succeededWithArtwork = try await runFFmpeg(
                executableURL: executableURL,
                arguments: conversionWithArtworkArguments(
                    sourceFileURL: sourceFileURL,
                    artworkFileURL: artworkFileURL,
                    destinationURL: destinationURL
                )
            )

            if succeededWithArtwork {
                return []
            }

            try await runRequiredFFmpeg(
                executableURL: executableURL,
                arguments: conversionArguments(sourceFileURL: sourceFileURL, destinationURL: destinationURL)
            )
            return [Self.failedFFmpegArtworkEmbeddingWarning]
        }
    }

    private func runRequiredFFmpeg(executableURL: URL, arguments: [String]) async throws {
        let result = try await commandRunner.run(executableURL: executableURL, arguments: arguments)

        guard result.terminationStatus == 0 else {
            throw AudioConversionError.conversionFailed(
                exitCode: result.terminationStatus,
                output: result.standardError.isEmpty ? result.standardOutput : result.standardError
            )
        }
    }

    private func conversionArguments(sourceFileURL: URL, destinationURL: URL) -> [String] {
        [
            "-y",
            "-i", sourceFileURL.path,
            destinationURL.path,
        ]
    }

    private func runFFmpeg(executableURL: URL, arguments: [String]) async throws -> Bool {
        let result = try await commandRunner.run(executableURL: executableURL, arguments: arguments)
        return result.terminationStatus == 0
    }

    private func conversionWithArtworkArguments(sourceFileURL: URL, artworkFileURL: URL, destinationURL: URL) -> [String] {
        [
            "-y",
            "-i", sourceFileURL.path,
            "-i", artworkFileURL.path,
            "-map", "0:a",
            "-map", "1:v",
            "-c:v", "mjpeg",
            "-id3v2_version", "3",
            "-metadata:s:v", "title=Album cover",
            "-metadata:s:v", "comment=Cover (front)",
            destinationURL.path,
        ]
    }

    private func convertedFileName(for episode: Episode) -> String {
        EpisodeFileName.fileName(for: episode, fileExtension: "mp3")
    }

    private static let failedArtworkPreparationWarning = "Cover art was not added because the artwork could not be downloaded or read."
    private static let failedMP3ArtworkTaggingWarning = "Cover art was not added because the MP3 could not be tagged."
    private static let failedFFmpegArtworkEmbeddingWarning = "Cover art was not added because ffmpeg could not embed it."
}

private enum ArtworkPreparationOutcome: Equatable {
    case notAvailable
    case prepared(URL)
    case failed(String)

    var warningMessage: String? {
        switch self {
        case .notAvailable, .prepared:
            return nil
        case .failed(let message):
            return message
        }
    }
}
