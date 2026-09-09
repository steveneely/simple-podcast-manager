import Foundation
import SimplePodcastManagerCore

/// Loads the same episode snapshot for startup and restore. A failed read must not
/// establish empty download/activity baselines or report a successful restore.
@MainActor
struct AppDataWorkflow {
    let library: MainViewModel
    let preparation: PreparationPreviewViewModel
    let automaticDownloads: AutomaticDownloadViewModel
    let activity: PodcastActivityViewModel
    let removalHistory: RemovedEpisodeHistoryViewModel
    let episodeStore: any EpisodeStateLoading

    func loadEpisodeState() async throws {
        let store = episodeStore
        let snapshot = try await Task.detached(priority: .userInitiated) {
            try store.loadEpisodeStateSnapshot()
        }.value
        try await preparation.applyPersistedState(
            preparedEpisodes: snapshot.preparedEpisodes,
            downloadedEpisodes: snapshot.downloadedEpisodes
        )
        automaticDownloads.applyPersistedState(snapshot.automaticDownloadState)
        activity.applyPersistedState(snapshot.podcastActivityState)
        removalHistory.applyPersistedState(snapshot.removedEpisodes)
    }

    func restore(
        from backupURL: URL,
        importBackup: @escaping @Sendable (URL) throws -> URL? = { try AppDataBackupService().importBackup(from: $0) }
    ) async throws -> URL? {
        let previousBackup = try await Task.detached {
            try importBackup(backupURL)
        }.value
        do {
            await library.load()
            if let message = library.lastErrorMessage {
                throw AppDataReloadError(message: message)
            }
            try await loadEpisodeState()
        } catch {
            let recoveryDetail = previousBackup.map { " Your previous data was backed up at \($0.path)." } ?? ""
            throw AppDataReloadError(message: "The backup was restored, but the app could not reload it: \(error.localizedDescription). Restart the app to retry.\(recoveryDetail)")
        }
        return previousBackup
    }
}

struct AppDataReloadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
