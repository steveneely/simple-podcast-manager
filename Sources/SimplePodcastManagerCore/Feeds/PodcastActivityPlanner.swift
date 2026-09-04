import Foundation

public struct PodcastActivityUpdate: Equatable, Sendable {
    public var state: PodcastActivityState
    public var discoveredEpisodeCount: Int

    public init(state: PodcastActivityState, discoveredEpisodeCount: Int) {
        self.state = state
        self.discoveredEpisodeCount = discoveredEpisodeCount
    }
}

public enum PodcastActivityPlanner {
    public static func updating(
        _ state: PodcastActivityState,
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>
    ) -> PodcastActivityState {
        update(
            state,
            subscriptions: subscriptions,
            episodes: episodes,
            refreshedSubscriptionIDs: refreshedSubscriptionIDs,
            failedSubscriptionIDs: failedSubscriptionIDs
        ).state
    }

    public static func update(
        _ state: PodcastActivityState,
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>
    ) -> PodcastActivityUpdate {
        let subscriptionsByID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
        var activityByPodcastID = Dictionary(uniqueKeysWithValues: state.podcasts.map { ($0.subscriptionID, $0) })
        activityByPodcastID = activityByPodcastID.filter { subscriptionsByID[$0.key] != nil }
        var discoveredEpisodeCount = 0

        for subscriptionID in refreshedSubscriptionIDs.subtracting(failedSubscriptionIDs) {
            guard let subscription = subscriptionsByID[subscriptionID], subscription.isEnabled else { continue }
            let currentEpisodes = episodes
                .filter { $0.subscriptionID == subscriptionID }
                .sorted(by: EpisodeSelector.isHigherPriority(_:than:))
            let currentIDs = currentEpisodes.map(\.id)
            let currentIDSet = Set(currentIDs)
            let newestDate = currentEpisodes.compactMap(\.publicationDate).max()

            guard var activity = activityByPodcastID[subscriptionID], activity.rssURL == subscription.rssURL else {
                activityByPodcastID[subscriptionID] = PodcastActivityEntry(
                    subscriptionID: subscriptionID,
                    rssURL: subscription.rssURL,
                    observedEpisodeIDs: currentIDs,
                    newestPublicationDate: newestDate
                )
                continue
            }

            let observedIDSet = Set(activity.observedEpisodeIDs)
            let candidateEpisodes: ArraySlice<Episode>
            if let anchorIndex = currentEpisodes.firstIndex(where: { observedIDSet.contains($0.id) }) {
                candidateEpisodes = currentEpisodes[..<anchorIndex]
            } else if let previousNewestDate = PublicationDateNormalizer.normalize(activity.newestPublicationDate) {
                candidateEpisodes = currentEpisodes[...].filter {
                    guard let publicationDate = $0.publicationDate else { return false }
                    return publicationDate > previousNewestDate
                }[...]
            } else {
                candidateEpisodes = []
            }
            discoveredEpisodeCount += Set(candidateEpisodes.map(\.id)).count

            activity.newEpisodeIDs.formIntersection(currentIDSet)
            activity.newEpisodeIDs.formUnion(candidateEpisodes.lazy.map(\.id))
            activity.rssURL = subscription.rssURL
            activity.observedEpisodeIDs = currentIDs
            activity.newestPublicationDate = newestDate
            activityByPodcastID[subscriptionID] = activity
        }

        return PodcastActivityUpdate(
            state: PodcastActivityState(podcasts: activityByPodcastID.values.sorted {
                $0.subscriptionID.uuidString < $1.subscriptionID.uuidString
            }),
            discoveredEpisodeCount: discoveredEpisodeCount
        )
    }

    public static func acknowledging(episodes: [Episode], in state: PodcastActivityState) -> PodcastActivityState {
        var updated = state
        let IDsBySubscription = Dictionary(grouping: episodes.compactMap { episode -> (UUID, String)? in
            guard let subscriptionID = episode.subscriptionID else { return nil }
            return (subscriptionID, episode.id)
        }, by: \.0).mapValues { Set($0.map(\.1)) }
        for index in updated.podcasts.indices {
            if let episodeIDs = IDsBySubscription[updated.podcasts[index].subscriptionID] {
                updated.podcasts[index].newEpisodeIDs.subtract(episodeIDs)
            }
        }
        return updated
    }

    public static func isInactive(
        _ activity: PodcastActivityEntry?,
        threshold: InactivePodcastThreshold,
        currentDate: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        guard let monthCount = threshold.monthCount,
              let newestPublicationDate = PublicationDateNormalizer.normalize(activity?.newestPublicationDate),
              let cutoff = calendar.date(byAdding: .month, value: -monthCount, to: currentDate)
        else { return false }
        return newestPublicationDate < cutoff
    }
}
