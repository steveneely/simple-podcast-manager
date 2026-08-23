import Foundation

public struct FeedActivityEpisodeKey: Hashable, Sendable {
    public var subscriptionID: UUID
    public var episodeID: String

    public init(subscriptionID: UUID, episodeID: String) {
        self.subscriptionID = subscriptionID
        self.episodeID = episodeID
    }

    public init?(episode: Episode) {
        guard let subscriptionID = episode.subscriptionID else { return nil }
        self.init(subscriptionID: subscriptionID, episodeID: episode.id)
    }
}

public enum FeedActivitySyncAcknowledgement {
    public static func episodesAcknowledged(
        preparedEpisodes: [PreparedEpisode],
        existingDeviceFiles: [FeedActivityEpisodeKey: URL],
        completedPlan: SyncPlan
    ) -> [Episode] {
        let copiedSourceURLs = Set(completedPlan.actions.compactMap { action -> URL? in
            guard case .copyToDevice(let sourceURL, _, _) = action else { return nil }
            return sourceURL.standardizedFileURL
        })
        let deletedTargetURLs = Set(completedPlan.actions.compactMap { action -> URL? in
            guard case .deleteFromDevice(let targetURL, _) = action else { return nil }
            return targetURL.standardizedFileURL
        })

        return preparedEpisodes.filter { prepared in
            let retainedExistingFile = FeedActivityEpisodeKey(episode: prepared.episode)
                .flatMap { existingDeviceFiles[$0] }
                .map { !deletedTargetURLs.contains($0.standardizedFileURL) } == true
            return retainedExistingFile
                || copiedSourceURLs.contains(prepared.preparedFileURL.standardizedFileURL)
        }.map(\.episode)
    }
}
