import Foundation

public struct FFmpegAudioConversionService: AudioConversionService {
    private let commandRunner: any CommandRunning
    private let artworkPreparationService: any ArtworkPreparationService
    private let metadataTaggingService: any MP3MetadataTaggingService
    private let bundledExecutableURL: URL?

    public init(
        commandRunner: any CommandRunning = ProcessCommandRunner(),
        artworkPreparationService: any ArtworkPreparationService = PodcastArtworkPreparationService(),
        metadataTaggingService: any MP3MetadataTaggingService = ID3MP3MetadataTaggingService(),
        bundledExecutableURL: URL? = Bundle.main.url(forResource: "ffmpeg", withExtension: nil)
    ) {
        self.commandRunner = commandRunner
        self.artworkPreparationService = artworkPreparationService
        self.metadataTaggingService = metadataTaggingService
        self.bundledExecutableURL = bundledExecutableURL
    }

    public func prepareAudio(
        for episode: Episode,
        sourceFileURL: URL,
        in workspaceURL: URL,
        settings: AppSettings
    ) async throws -> PreparedEpisode {
        let audioPreparation = try await prepareMP3Audio(
            sourceFileURL: sourceFileURL,
            episode: episode,
            workspaceURL: workspaceURL,
            settings: settings
        )
        let intermediateFileURL = audioPreparation.mp3FileURL == sourceFileURL
            ? nil
            : audioPreparation.mp3FileURL
        defer {
            if let intermediateFileURL {
                try? FileManager.default.removeItem(at: intermediateFileURL)
            }
        }
        let artworkPreparation = try await preparedArtwork(
            for: episode,
            in: workspaceURL,
            allowsInsecureHTTP: settings.allowsInsecureDownloads
        )
        let destinationURL = try preparedDestinationURL(for: episode, in: workspaceURL)

        do {
            try metadataTaggingService.writeMetadata(
                sourceFileURL: audioPreparation.mp3FileURL,
                episodeTitle: EpisodeID3Title.title(
                    for: episode,
                    prefixesPublicationDate: settings.prefixesPublicationDateInEpisodeTitles
                ),
                podcastTitle: episode.podcastTitle,
                genre: settings.mp3Genre,
                artworkFileURL: artworkPreparation.fileURL,
                destinationFileURL: destinationURL
            )
        } catch {
            throw AudioConversionError.metadataWritingFailed(error.localizedDescription)
        }

        return PreparedEpisode(
            episode: episode,
            sourceFileURL: sourceFileURL,
            preparedFileURL: destinationURL,
            preparationAction: audioPreparation.action,
            preparationWarnings: artworkPreparation.warningMessage.map { [$0] }
        )
    }

    private func prepareMP3Audio(
        sourceFileURL: URL,
        episode: Episode,
        workspaceURL: URL,
        settings: AppSettings
    ) async throws -> AudioPreparation {
        guard sourceFileURL.pathExtension.lowercased() != "mp3" else {
            return AudioPreparation(mp3FileURL: sourceFileURL, action: .passthroughMP3)
        }

        guard let executableURL = ffmpegExecutableURL(from: settings) else {
            throw AudioConversionError.ffmpegNotConfigured
        }

        let convertedFileURL = workspaceURL.appending(
            path: EpisodeFileName.fileName(for: episode, fileExtension: "mp3"),
            directoryHint: .notDirectory
        )
        let result = try await commandRunner.run(
            executableURL: executableURL,
            arguments: ["-y", "-i", sourceFileURL.path, convertedFileURL.path]
        )
        guard result.terminationStatus == 0 else {
            throw AudioConversionError.conversionFailed(
                exitCode: result.terminationStatus,
                output: result.standardError.isEmpty ? result.standardOutput : result.standardError
            )
        }

        return AudioPreparation(mp3FileURL: convertedFileURL, action: .convertedToMP3)
    }

    private func ffmpegExecutableURL(from settings: AppSettings) -> URL? {
        if let configuredPath = settings.ffmpegExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredPath.isEmpty {
            return URL(fileURLWithPath: configuredPath, isDirectory: false)
        }
        return bundledExecutableURL
    }

    private func preparedArtwork(
        for episode: Episode,
        in workspaceURL: URL,
        allowsInsecureHTTP: Bool
    ) async throws -> ArtworkPreparation {
        guard let artworkURL = episode.artworkURL else {
            return ArtworkPreparation()
        }

        do {
            return ArtworkPreparation(
                fileURL: try await artworkPreparationService.prepareArtwork(
                    from: artworkURL,
                    in: workspaceURL,
                    allowsInsecureHTTP: allowsInsecureHTTP
                )
            )
        } catch HTTPDataResourceLoadingError.insecureDownloadRequiresPermission {
            throw HTTPDataResourceLoadingError.insecureDownloadRequiresPermission
        } catch {
            return ArtworkPreparation(warningMessage: Self.failedArtworkPreparationWarning)
        }
    }

    private func preparedDestinationURL(for episode: Episode, in workspaceURL: URL) throws -> URL {
        let directoryURL = workspaceURL.appending(path: "prepared", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appending(
            path: EpisodeFileName.fileName(for: episode, fileExtension: "mp3"),
            directoryHint: .notDirectory
        )
    }

    private static let failedArtworkPreparationWarning =
        "Cover art was not added because the artwork could not be downloaded or read."
}

private struct AudioPreparation {
    var mp3FileURL: URL
    var action: PreparationAction
}

private struct ArtworkPreparation {
    var fileURL: URL?
    var warningMessage: String?
}
