import Foundation

public enum FeedActivityPlanner {
    public static func updating(
        _ state: FeedActivityState,
        subscriptions: [FeedSubscription],
        episodes: [Episode],
        refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>,
        openSubscriptionID: UUID?
    ) -> FeedActivityState {
        let subscriptionsByID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
        var feedsByID = Dictionary(uniqueKeysWithValues: state.feeds.map { ($0.subscriptionID, $0) })
        feedsByID = feedsByID.filter { subscriptionsByID[$0.key] != nil }

        for subscriptionID in refreshedSubscriptionIDs.subtracting(failedSubscriptionIDs) {
            guard let subscription = subscriptionsByID[subscriptionID], subscription.isEnabled else { continue }
            let currentEpisodes = episodes
                .filter { $0.subscriptionID == subscriptionID }
                .sorted(by: EpisodeSelector.isHigherPriority(_:than:))
            let currentIDs = currentEpisodes.map(\.id)
            let currentIDSet = Set(currentIDs)
            let newestDate = currentEpisodes.compactMap(\.publicationDate).max()

            guard var feed = feedsByID[subscriptionID], feed.rssURL == subscription.rssURL else {
                feedsByID[subscriptionID] = FeedActivityFeedState(
                    subscriptionID: subscriptionID,
                    rssURL: subscription.rssURL,
                    observedEpisodeIDs: currentIDs,
                    newestPublicationDate: newestDate
                )
                continue
            }

            let observedIDSet = Set(feed.observedEpisodeIDs)
            let candidateEpisodes: ArraySlice<Episode>
            if let anchorIndex = currentEpisodes.firstIndex(where: { observedIDSet.contains($0.id) }) {
                candidateEpisodes = currentEpisodes[..<anchorIndex]
            } else if let previousNewestDate = PublicationDateNormalizer.normalize(feed.newestPublicationDate) {
                candidateEpisodes = currentEpisodes[...].filter {
                    guard let publicationDate = $0.publicationDate else { return false }
                    return publicationDate > previousNewestDate
                }[...]
            } else {
                candidateEpisodes = []
            }

            feed.newEpisodeIDs.formIntersection(currentIDSet)
            if openSubscriptionID != subscriptionID {
                feed.newEpisodeIDs.formUnion(candidateEpisodes.lazy.map(\.id))
            }
            feed.rssURL = subscription.rssURL
            feed.observedEpisodeIDs = currentIDs
            feed.newestPublicationDate = newestDate
            feedsByID[subscriptionID] = feed
        }

        return FeedActivityState(feeds: feedsByID.values.sorted {
            $0.subscriptionID.uuidString < $1.subscriptionID.uuidString
        })
    }

    public static func markingSeen(subscriptionID: UUID, in state: FeedActivityState) -> FeedActivityState {
        var updated = state
        guard let index = updated.feeds.firstIndex(where: { $0.subscriptionID == subscriptionID }) else { return state }
        updated.feeds[index].newEpisodeIDs = []
        return updated
    }

    public static func acknowledging(episodes: [Episode], in state: FeedActivityState) -> FeedActivityState {
        var updated = state
        let IDsBySubscription = Dictionary(grouping: episodes.compactMap { episode -> (UUID, String)? in
            guard let subscriptionID = episode.subscriptionID else { return nil }
            return (subscriptionID, episode.id)
        }, by: \.0).mapValues { Set($0.map(\.1)) }
        for index in updated.feeds.indices {
            if let episodeIDs = IDsBySubscription[updated.feeds[index].subscriptionID] {
                updated.feeds[index].newEpisodeIDs.subtract(episodeIDs)
            }
        }
        return updated
    }

    public static func isInactive(
        _ feed: FeedActivityFeedState?,
        threshold: InactivePodcastThreshold,
        currentDate: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        guard let monthCount = threshold.monthCount,
              let newestPublicationDate = PublicationDateNormalizer.normalize(feed?.newestPublicationDate),
              let cutoff = calendar.date(byAdding: .month, value: -monthCount, to: currentDate)
        else { return false }
        return newestPublicationDate < cutoff
    }
}
