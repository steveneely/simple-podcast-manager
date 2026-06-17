import Foundation

public struct FFmpegAudioConversionService: AudioConversionService {
    private let commandRunner: any CommandRunning
    private let artworkPreparationService: any ArtworkPreparationService
    private let bundledExecutableURL: URL?

    public init(
        commandRunner: any CommandRunning = ProcessCommandRunner(),
        artworkPreparationService: any ArtworkPreparationService = PodcastArtworkPreparationService(),
        bundledExecutableURL: URL? = Bundle.main.url(forResource: "ffmpeg", withExtension: nil)
    ) {
        self.commandRunner = commandRunner
        self.artworkPreparationService = artworkPreparationService
        self.bundledExecutableURL = bundledExecutableURL
    }

    public func prepareAudio(for episode: Episode, sourceFileURL: URL, in workspaceURL: URL, settings: AppSettings) async throws -> PreparedEpisode {
        let artworkFileURL = await preparedArtworkFileURL(for: episode, in: workspaceURL)

        if sourceFileURL.pathExtension.lowercased() == "mp3" {
            guard let artworkFileURL, let executableURL = ffmpegExecutableURL(from: settings) else {
                return PreparedEpisode(
                    episode: episode,
                    sourceFileURL: sourceFileURL,
                    preparedFileURL: sourceFileURL,
                    preparationAction: .passthroughMP3
                )
            }

            let destinationURL = try taggedMP3DestinationURL(for: episode, in: workspaceURL)
            guard try await runFFmpeg(
                executableURL: executableURL,
                arguments: mp3ArtworkArguments(sourceFileURL: sourceFileURL, artworkFileURL: artworkFileURL, destinationURL: destinationURL)
            ) else {
                return PreparedEpisode(
                    episode: episode,
                    sourceFileURL: sourceFileURL,
                    preparedFileURL: sourceFileURL,
                    preparationAction: .passthroughMP3
                )
            }

            return PreparedEpisode(
                episode: episode,
                sourceFileURL: sourceFileURL,
                preparedFileURL: destinationURL,
                preparationAction: .passthroughMP3
            )
        }

        guard let executableURL = ffmpegExecutableURL(from: settings) else {
            throw AudioConversionError.ffmpegNotConfigured
        }

        let destinationURL = workspaceURL.appending(path: convertedFileName(for: episode), directoryHint: .notDirectory)
        try await convertToMP3(
            executableURL: executableURL,
            sourceFileURL: sourceFileURL,
            artworkFileURL: artworkFileURL,
            destinationURL: destinationURL
        )

        return PreparedEpisode(
            episode: episode,
            sourceFileURL: sourceFileURL,
            preparedFileURL: destinationURL,
            preparationAction: .convertedToMP3
        )
    }

    private func ffmpegExecutableURL(from settings: AppSettings) -> URL? {
        if let ffmpegExecutablePath = settings.ffmpegExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ffmpegExecutablePath.isEmpty {
            return URL(fileURLWithPath: ffmpegExecutablePath, isDirectory: false)
        }

        return bundledExecutableURL
    }

    private func preparedArtworkFileURL(for episode: Episode, in workspaceURL: URL) async -> URL? {
        guard let artworkURL = episode.artworkURL else { return nil }

        return try? await artworkPreparationService.prepareArtwork(from: artworkURL, in: workspaceURL)
    }

    private func taggedMP3DestinationURL(for episode: Episode, in workspaceURL: URL) throws -> URL {
        let directoryURL = workspaceURL.appending(path: "prepared", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appending(path: convertedFileName(for: episode), directoryHint: .notDirectory)
    }

    private func convertToMP3(
        executableURL: URL,
        sourceFileURL: URL,
        artworkFileURL: URL?,
        destinationURL: URL
    ) async throws {
        let arguments: [String]
        if let artworkFileURL {
            arguments = conversionWithArtworkArguments(
                sourceFileURL: sourceFileURL,
                artworkFileURL: artworkFileURL,
                destinationURL: destinationURL
            )
        } else {
            arguments = [
                "-y",
                "-i", sourceFileURL.path,
                destinationURL.path,
            ]
        }

        let result = try await commandRunner.run(executableURL: executableURL, arguments: arguments)

        guard result.terminationStatus == 0 else {
            throw AudioConversionError.conversionFailed(
                exitCode: result.terminationStatus,
                output: result.standardError.isEmpty ? result.standardOutput : result.standardError
            )
        }
    }

    private func runFFmpeg(executableURL: URL, arguments: [String]) async throws -> Bool {
        let result = try await commandRunner.run(executableURL: executableURL, arguments: arguments)
        return result.terminationStatus == 0
    }

    private func mp3ArtworkArguments(sourceFileURL: URL, artworkFileURL: URL, destinationURL: URL) -> [String] {
        [
            "-y",
            "-i", sourceFileURL.path,
            "-i", artworkFileURL.path,
            "-map", "0:a",
            "-map", "1:v",
            "-c:a", "copy",
            "-c:v", "mjpeg",
            "-id3v2_version", "3",
            "-metadata:s:v", "title=Album cover",
            "-metadata:s:v", "comment=Cover (front)",
            destinationURL.path,
        ]
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
}
