import Foundation

public struct FFmpegAudioConversionService: AudioConversionService {
    private let commandRunner: any CommandRunning

    public init(commandRunner: any CommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func prepareAudio(for episode: Episode, sourceFileURL: URL, in workspaceURL: URL, settings: AppSettings) async throws -> PreparedEpisode {
        if sourceFileURL.pathExtension.lowercased() == "mp3" {
            return PreparedEpisode(
                episode: episode,
                sourceFileURL: sourceFileURL,
                preparedFileURL: sourceFileURL,
                preparationAction: .passthroughMP3
            )
        }

        guard let executableURL = ffmpegExecutableURL(from: settings) else {
            throw AudioConversionError.ffmpegNotConfigured
        }

        let destinationURL = workspaceURL.appending(path: convertedFileName(for: episode), directoryHint: .notDirectory)
        let result = try await commandRunner.run(
            executableURL: executableURL,
            arguments: [
                "-y",
                "-i", sourceFileURL.path,
                destinationURL.path,
            ]
        )

        guard result.terminationStatus == 0 else {
            throw AudioConversionError.conversionFailed(
                exitCode: result.terminationStatus,
                output: result.standardError.isEmpty ? result.standardOutput : result.standardError
            )
        }

        return PreparedEpisode(
            episode: episode,
            sourceFileURL: sourceFileURL,
            preparedFileURL: destinationURL,
            preparationAction: .convertedToMP3
        )
    }

    private func ffmpegExecutableURL(from settings: AppSettings) -> URL? {
        guard let ffmpegExecutablePath = settings.ffmpegExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ffmpegExecutablePath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: ffmpegExecutablePath, isDirectory: false)
    }

    private func convertedFileName(for episode: Episode) -> String {
        EpisodeFileName.fileName(for: episode, fileExtension: "mp3")
    }
}
