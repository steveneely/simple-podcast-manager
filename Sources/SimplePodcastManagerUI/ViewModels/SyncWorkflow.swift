import Foundation
import SimplePodcastManagerCore

/// Applies history and local cleanup to the outcome of one reviewed sync.
@MainActor
struct SyncWorkflow {
    let execution: SyncExecutionViewModel
    let preparation: PreparationPreviewViewModel
    let activity: PodcastActivityViewModel
    let removalHistory: RemovedEpisodeHistoryViewModel
    let deviceLibrary: DeviceLibraryViewModel

    func run(
        plan: SyncPlan?,
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        deleteDownloadsAfterSync: Bool
    ) async -> Bool {
        let preparedEpisodes = preparation.preparedEpisodes
        let existingFiles = Dictionary(uniqueKeysWithValues: preparedEpisodes.compactMap { prepared -> (PodcastActivityEpisodeKey, URL)? in
            guard let fileURL = deviceLibrary.file(for: prepared.episode),
                  let key = PodcastActivityEpisodeKey(episode: prepared.episode) else { return nil }
            return (key, fileURL.standardizedFileURL)
        })
        let filesBySubscriptionID = Dictionary(uniqueKeysWithValues: subscriptions.map {
            ($0.id, deviceLibrary.files(for: $0))
        })
        let episodesBySubscriptionID = Dictionary(grouping: episodes.compactMap { episode -> (UUID, Episode)? in
            guard let subscriptionID = episode.subscriptionID else { return nil }
            return (subscriptionID, episode)
        }, by: \.0).mapValues { $0.map(\.1) }

        await execution.sync(plan: plan)
        guard let result = execution.lastResult else { return false }

        removalHistory.recordDeletedEpisodes(
            deletedTargetURLs: result.deletedTargetURLs,
            filesBySubscriptionID: filesBySubscriptionID,
            episodesBySubscriptionID: episodesBySubscriptionID,
            deviceName: plan?.device.name,
            removedAt: result.finishedAt ?? result.startedAt
        )
        guard execution.lastErrorMessage == nil, let completedPlan = execution.lastPlan else { return false }

        let acknowledgedEpisodes = PodcastActivitySyncAcknowledgement.episodesAcknowledged(
            preparedEpisodes: preparedEpisodes,
            existingDeviceFiles: existingFiles,
            completedPlan: completedPlan
        )
        await activity.acknowledge(acknowledgedEpisodes)
        if deleteDownloadsAfterSync {
            let acknowledgedKeys = Set(acknowledgedEpisodes.compactMap(PodcastActivityEpisodeKey.init))
            await preparation.removePreparedEpisodes(preparedEpisodes.filter {
                PodcastActivityEpisodeKey(episode: $0.episode).map(acknowledgedKeys.contains) == true
            })
        }
        return true
    }
}
