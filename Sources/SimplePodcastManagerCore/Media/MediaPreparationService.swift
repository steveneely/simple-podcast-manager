import Foundation

public struct MediaPreparationService: Sendable {
    private let downloadService: any DownloadService
    private let audioConversionService: any AudioConversionService
    private let workspaceProvider: any MediaWorkspaceProviding

    public init(
        downloadService: any DownloadService = URLSessionDownloadService(),
        audioConversionService: any AudioConversionService = FFmpegAudioConversionService(),
        workspaceProvider: any MediaWorkspaceProviding = PersistentMediaWorkspaceProvider()
    ) {
        self.downloadService = downloadService
        self.audioConversionService = audioConversionService
        self.workspaceProvider = workspaceProvider
    }

    public func prepareEpisode(
        _ episode: Episode,
        settings: AppSettings
    ) async -> MediaPreparationResult {
        var downloadedFileURL: URL?
        var preparedFileURL: URL?
        do {
            try Task.checkCancellation()
            let workspaceURL = try workspaceProvider.makeWorkspace()
            let sourceFileURL = try await downloadService.download(
                episode,
                into: workspaceURL,
                allowsInsecureHTTP: settings.allowsInsecureDownloads
            )
            downloadedFileURL = sourceFileURL
            try Task.checkCancellation()
            let preparedEpisode = try await audioConversionService.prepareAudio(
                for: episode,
                sourceFileURL: sourceFileURL,
                in: workspaceURL,
                settings: settings
            )
            preparedFileURL = preparedEpisode.preparedFileURL
            try Task.checkCancellation()
            return .prepared(preparedEpisode)
        } catch is CancellationError {
            if let preparedFileURL, preparedFileURL != downloadedFileURL {
                try? FileManager.default.removeItem(at: preparedFileURL)
            }
            if let downloadedFileURL {
                try? FileManager.default.removeItem(at: downloadedFileURL)
            }
            return .cancelled
        } catch {
            // A failed preparation should not leave an incomplete local download behind.
            if let downloadedFileURL {
                try? FileManager.default.removeItem(at: downloadedFileURL)
            }
            if Task.isCancelled { return .cancelled }
            return .failed(
                PreparationFailure(
                    episode: episode,
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                    reason: requiresInsecureDownloadPermission(error)
                        ? .insecureDownloadRequiresPermission
                        : .other
                )
            )
        }
    }

    private func requiresInsecureDownloadPermission(_ error: Error) -> Bool {
        error as? DownloadServiceError == .insecureDownloadRequiresPermission
            || error as? HTTPDataResourceLoadingError == .insecureDownloadRequiresPermission
    }
}
