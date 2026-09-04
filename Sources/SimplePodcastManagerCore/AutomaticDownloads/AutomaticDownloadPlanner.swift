import Foundation

public struct AutomaticDownloadPlan: Equatable, Sendable {
    public var state: AutomaticDownloadState
    public var episodesToDownload: [Episode]

    public init(state: AutomaticDownloadState, episodesToDownload: [Episode]) {
        self.state = state
        self.episodesToDownload = episodesToDownload
    }
}

public enum AutomaticDownloadPlanner {
    public static func makePlan(
        state: AutomaticDownloadState,
        subscriptions: [FeedSubscription],
        episodes: [Episode],
        refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>,
        downloadedEpisodeIDs: Set<AutomaticDownloadEpisodeID>,
        limit: AutomaticDownloadLimit
    ) -> AutomaticDownloadPlan {
        let subscriptionsByID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
        let enabledSubscriptionIDs = Set(subscriptions.filter(\.isEnabled).map(\.id))
        let episodesBySubscription = Dictionary(grouping: episodes.compactMap { episode -> (UUID, Episode)? in
            guard let subscriptionID = episode.subscriptionID else { return nil }
            return (subscriptionID, episode)
        }, by: { $0.0 })

        var statesBySubscription = Dictionary(
            uniqueKeysWithValues: state.feeds
                .filter { subscriptionsByID[$0.subscriptionID] != nil }
                .map { ($0.subscriptionID, $0) }
        )
        var plannedEpisodes: [Episode] = []

        for subscription in subscriptions {
            guard subscription.isEnabled else {
                statesBySubscription.removeValue(forKey: subscription.id)
                continue
            }
            guard refreshedSubscriptionIDs.contains(subscription.id) else { continue }
            guard !failedSubscriptionIDs.contains(subscription.id) else { continue }

            let currentEpisodes = (episodesBySubscription[subscription.id] ?? [])
                .map(\.1)
                .sorted(by: EpisodeSelector.isHigherPriority(_:than:))
            let currentEpisodeIDs = uniqueEpisodeIDs(currentEpisodes.map(\.id))
            let currentEpisodeIDSet = Set(currentEpisodeIDs)

            guard var feedState = statesBySubscription[subscription.id], feedState.rssURL == subscription.rssURL else {
                statesBySubscription[subscription.id] = AutomaticDownloadFeedState(
                    subscriptionID: subscription.id,
                    rssURL: subscription.rssURL,
                    observedEpisodeIDs: currentEpisodeIDs
                )
                continue
            }

            let previouslyObservedEpisodeIDs = Set(feedState.observedEpisodeIDs)
            let newEpisodes = currentEpisodes.filter { !previouslyObservedEpisodeIDs.contains($0.id) }
            let olderObservedEpisodeIDs = uniqueEpisodeIDs(feedState.observedEpisodeIDs.filter {
                !currentEpisodeIDSet.contains($0)
            })
            feedState.observedEpisodeIDs = currentEpisodeIDs + olderObservedEpisodeIDs

            if limit != .off, subscription.includesInAutomaticDownloads {
                let selectedNewEpisodes: ArraySlice<Episode>
                if let maximumEpisodeCount = limit.maximumEpisodeCount {
                    selectedNewEpisodes = newEpisodes.prefix(maximumEpisodeCount)
                } else {
                    selectedNewEpisodes = newEpisodes[...]
                }
                feedState.pendingEpisodeIDs.formUnion(selectedNewEpisodes.map(\.id))
            } else {
                feedState.pendingEpisodeIDs.removeAll()
            }

            let downloadedIDsForSubscription = Set(downloadedEpisodeIDs.compactMap {
                $0.subscriptionID == subscription.id ? $0.episodeID : nil
            })
            feedState.pendingEpisodeIDs.subtract(downloadedIDsForSubscription)
            feedState.pendingEpisodeIDs.formIntersection(currentEpisodeIDSet)

            plannedEpisodes.append(contentsOf: currentEpisodes.filter {
                feedState.pendingEpisodeIDs.contains($0.id)
            })
            statesBySubscription[subscription.id] = feedState
        }

        statesBySubscription = statesBySubscription.filter { enabledSubscriptionIDs.contains($0.key) }
        let updatedState = AutomaticDownloadState(
            feeds: statesBySubscription.values.sorted {
                $0.subscriptionID.uuidString < $1.subscriptionID.uuidString
            }
        )
        return AutomaticDownloadPlan(
            state: updatedState,
            episodesToDownload: plannedEpisodes.sorted(by: EpisodeSelector.isHigherPriority(_:than:))
        )
    }

    public static func applyingPreferences(
        to state: AutomaticDownloadState,
        subscriptions: [FeedSubscription],
        limit: AutomaticDownloadLimit
    ) -> AutomaticDownloadState {
        let subscriptionsByID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
        let feeds = state.feeds.compactMap { feedState -> AutomaticDownloadFeedState? in
            guard let subscription = subscriptionsByID[feedState.subscriptionID], subscription.isEnabled else {
                return nil
            }
            var updatedState = feedState
            if limit == .off || !subscription.includesInAutomaticDownloads {
                updatedState.pendingEpisodeIDs.removeAll()
            }
            return updatedState
        }
        return AutomaticDownloadState(feeds: feeds)
    }

    public static func activatingCurrentlyNewEpisodes(
        in state: AutomaticDownloadState,
        subscriptionIDs: Set<UUID>,
        subscriptions: [FeedSubscription],
        episodes: [Episode],
        newEpisodeIDsBySubscription: [UUID: Set<String>],
        downloadedEpisodeIDs: Set<AutomaticDownloadEpisodeID>,
        limit: AutomaticDownloadLimit
    ) -> AutomaticDownloadPlan {
        var updatedState = applyingPreferences(
            to: state,
            subscriptions: subscriptions,
            limit: limit
        )
        guard limit != .off, !subscriptionIDs.isEmpty else {
            return AutomaticDownloadPlan(state: updatedState, episodesToDownload: [])
        }

        let subscriptionsByID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
        let episodesBySubscription = Dictionary(grouping: episodes.compactMap { episode -> (UUID, Episode)? in
            guard let subscriptionID = episode.subscriptionID else { return nil }
            return (subscriptionID, episode)
        }, by: { $0.0 })
        var statesBySubscription = Dictionary(
            uniqueKeysWithValues: updatedState.feeds.map { ($0.subscriptionID, $0) }
        )
        var selectedEpisodes: [Episode] = []

        for subscriptionID in subscriptionIDs {
            guard let subscription = subscriptionsByID[subscriptionID],
                  subscription.isEnabled,
                  subscription.includesInAutomaticDownloads
            else { continue }

            let currentEpisodes = (episodesBySubscription[subscriptionID] ?? [])
                .map(\.1)
                .sorted(by: EpisodeSelector.isHigherPriority(_:than:))
            let newEpisodeIDs = newEpisodeIDsBySubscription[subscriptionID] ?? []
            let downloadedIDs = Set(downloadedEpisodeIDs.compactMap {
                $0.subscriptionID == subscriptionID ? $0.episodeID : nil
            })
            let eligibleEpisodes = currentEpisodes.filter {
                newEpisodeIDs.contains($0.id) && !downloadedIDs.contains($0.id)
            }
            let activatedEpisodes: [Episode]
            if let maximumEpisodeCount = limit.maximumEpisodeCount {
                activatedEpisodes = Array(eligibleEpisodes.prefix(maximumEpisodeCount))
            } else {
                activatedEpisodes = eligibleEpisodes
            }

            var feedState = statesBySubscription[subscriptionID]
                ?? AutomaticDownloadFeedState(
                    subscriptionID: subscriptionID,
                    rssURL: subscription.rssURL,
                    observedEpisodeIDs: uniqueEpisodeIDs(currentEpisodes.map(\.id))
                )
            guard feedState.rssURL == subscription.rssURL else { continue }
            feedState.pendingEpisodeIDs.formUnion(activatedEpisodes.map(\.id))
            feedState.pendingEpisodeIDs.subtract(downloadedIDs)
            statesBySubscription[subscriptionID] = feedState
            selectedEpisodes.append(contentsOf: activatedEpisodes)
        }

        updatedState.feeds = statesBySubscription.values.sorted {
            $0.subscriptionID.uuidString < $1.subscriptionID.uuidString
        }
        return AutomaticDownloadPlan(
            state: updatedState,
            episodesToDownload: selectedEpisodes.sorted(by: EpisodeSelector.isHigherPriority(_:than:))
        )
    }

    public static func markingDownloaded(
        _ downloadedEpisodes: [Episode],
        in state: AutomaticDownloadState
    ) -> AutomaticDownloadState {
        let downloadedIDs = Set(downloadedEpisodes.compactMap(AutomaticDownloadEpisodeID.init))
        let feeds = state.feeds.map { feedState -> AutomaticDownloadFeedState in
            var updatedState = feedState
            let episodeIDs = downloadedIDs.compactMap {
                $0.subscriptionID == feedState.subscriptionID ? $0.episodeID : nil
            }
            updatedState.pendingEpisodeIDs.subtract(episodeIDs)
            return updatedState
        }
        return AutomaticDownloadState(feeds: feeds)
    }

    private static func uniqueEpisodeIDs(_ episodeIDs: [String]) -> [String] {
        var seenEpisodeIDs: Set<String> = []
        return episodeIDs.filter { seenEpisodeIDs.insert($0).inserted }
    }
}
