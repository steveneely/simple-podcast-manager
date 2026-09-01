import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct FeedRefreshCoordinatorTests {
    @Test
    func topLevelRefreshFailureIsAppliedToActivityAndAutomaticDownloads() async {
        let subscription = makeSubscription(number: 1)
        let episode = makeEpisode(number: 1, subscription: subscription)
        let summary = FeedSummary(subscriptionID: subscription.id, title: subscription.title)
        let preview = StubFeedRefreshPreview(
            allEpisodes: [episode],
            feedSummaries: [subscription.id: summary],
            lastErrorMessage: "Network unavailable"
        )
        let activity = StubFeedRefreshActivity()
        let automaticDownloads = StubFeedRefreshAutomaticDownloads()
        let preparation = StubFeedRefreshPreparation()
        let subscriptionLibrary = StubFeedRefreshSubscriptionLibrary(
            feedSubscriptions: [subscription],
            settings: AppSettings(automaticDownloadLimit: .latest1)
        )
        let coordinator = FeedRefreshCoordinator(
            feedPreview: preview,
            subscriptionLibrary: subscriptionLibrary,
            feedActivity: activity,
            automaticDownloads: automaticDownloads,
            episodePreparation: preparation
        )

        let outcome = await coordinator.refresh(
            .allEnabledSubscriptions([subscription]),
            openSubscriptionID: subscription.id
        )

        #expect(preview.allSubscriptionsRefreshes == [[subscription]])
        #expect(activity.refreshedSubscriptionIDs == [subscription.id])
        #expect(activity.failedSubscriptionIDs == [subscription.id])
        #expect(activity.openSubscriptionID == subscription.id)
        #expect(automaticDownloads.refreshedSubscriptionIDs == [subscription.id])
        #expect(automaticDownloads.failedSubscriptionIDs == [subscription.id])
        #expect(automaticDownloads.limit == .latest1)
        #expect(subscriptionLibrary.appliedFeedSummaries == [summary])
        #expect(!outcome.attemptedAutomaticDownloads)
    }

    @Test
    func targetedRefreshPreparesEpisodesAndAcknowledgesOnlySuccessfulDownloads() async {
        let subscription = makeSubscription(number: 1)
        let unrelatedSubscription = makeSubscription(number: 2)
        let downloadedEpisode = makeEpisode(number: 1, subscription: subscription)
        let permissionEpisode = makeEpisode(number: 2, subscription: subscription)
        let preview = StubFeedRefreshPreview(
            allEpisodes: [downloadedEpisode, permissionEpisode],
            failures: [FeedFetchFailure(
                subscriptionID: unrelatedSubscription.id,
                subscriptionTitle: unrelatedSubscription.title,
                message: "Unrelated failure"
            )]
        )
        let activity = StubFeedRefreshActivity()
        let automaticDownloads = StubFeedRefreshAutomaticDownloads(
            episodesToReturn: [downloadedEpisode, permissionEpisode]
        )
        let preparation = StubFeedRefreshPreparation(
            downloadedEpisodeIDsAfterPreparation: [downloadedEpisode.id],
            insecurePermissionEpisodeIDs: [permissionEpisode.id]
        )
        let subscriptionLibrary = StubFeedRefreshSubscriptionLibrary(
            feedSubscriptions: [subscription, unrelatedSubscription],
            settings: AppSettings(automaticDownloadLimit: .allNew)
        )
        let coordinator = FeedRefreshCoordinator(
            feedPreview: preview,
            subscriptionLibrary: subscriptionLibrary,
            feedActivity: activity,
            automaticDownloads: automaticDownloads,
            episodePreparation: preparation
        )

        let outcome = await coordinator.refresh(
            .subscription(subscription),
            openSubscriptionID: nil
        )

        #expect(preview.subscriptionRefreshes == [subscription])
        #expect(activity.failedSubscriptionIDs.isEmpty)
        #expect(automaticDownloads.failedSubscriptionIDs.isEmpty)
        #expect(preparation.preparedEpisodes == [downloadedEpisode, permissionEpisode])
        #expect(automaticDownloads.markedDownloadedEpisodes == [downloadedEpisode])
        #expect(outcome.episodesRequiringInsecureDownloadPermission == [permissionEpisode])
        #expect(outcome.attemptedAutomaticDownloads)
    }

    private func makeSubscription(number: Int) -> FeedSubscription {
        FeedSubscription(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
            title: "Podcast \(number)",
            rssURL: URL(string: "https://example.com/feed-\(number).xml")!
        )
    }

    private func makeEpisode(number: Int, subscription: FeedSubscription) -> Episode {
        Episode(
            id: "episode-\(number)",
            subscriptionID: subscription.id,
            podcastTitle: subscription.title,
            title: "Episode \(number)",
            enclosureURL: URL(string: "https://example.com/episode-\(number).mp3")!,
            sourceFeedURL: subscription.rssURL
        )
    }
}

@MainActor
private final class StubFeedRefreshSubscriptionLibrary: FeedRefreshSubscriptionUpdating {
    var feedSubscriptions: [FeedSubscription]
    var settings: AppSettings
    private(set) var appliedFeedSummaries: [FeedSummary] = []

    init(feedSubscriptions: [FeedSubscription], settings: AppSettings) {
        self.feedSubscriptions = feedSubscriptions
        self.settings = settings
    }

    func applyFeedSummaries(_ feedSummaries: [FeedSummary]) {
        appliedFeedSummaries = feedSummaries
    }
}

@MainActor
private final class StubFeedRefreshPreview: FeedRefreshPreviewing {
    var allEpisodes: [Episode]
    var failures: [FeedFetchFailure]
    var feedSummaries: [UUID: FeedSummary]
    var lastErrorMessage: String?
    private(set) var allSubscriptionsRefreshes: [[FeedSubscription]] = []
    private(set) var subscriptionRefreshes: [FeedSubscription] = []
    private(set) var newSubscriptionsRefreshes: [[FeedSubscription]] = []

    init(
        allEpisodes: [Episode] = [],
        failures: [FeedFetchFailure] = [],
        feedSummaries: [UUID: FeedSummary] = [:],
        lastErrorMessage: String? = nil
    ) {
        self.allEpisodes = allEpisodes
        self.failures = failures
        self.feedSummaries = feedSummaries
        self.lastErrorMessage = lastErrorMessage
    }

    func refreshPreview(for subscriptions: [FeedSubscription]) async {
        allSubscriptionsRefreshes.append(subscriptions)
    }

    func refreshPreview(for subscription: FeedSubscription) async {
        subscriptionRefreshes.append(subscription)
    }

    func refreshPreview(forNewSubscriptions subscriptions: [FeedSubscription]) async {
        newSubscriptionsRefreshes.append(subscriptions)
    }
}

@MainActor
private final class StubFeedRefreshActivity: FeedRefreshActivityUpdating {
    private(set) var refreshedSubscriptionIDs: Set<UUID> = []
    private(set) var failedSubscriptionIDs: Set<UUID> = []
    private(set) var openSubscriptionID: UUID?

    func updateAfterRefresh(
        subscriptions: [FeedSubscription],
        episodes: [Episode],
        refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>,
        openSubscriptionID: UUID?
    ) async {
        self.refreshedSubscriptionIDs = refreshedSubscriptionIDs
        self.failedSubscriptionIDs = failedSubscriptionIDs
        self.openSubscriptionID = openSubscriptionID
    }
}

@MainActor
private final class StubFeedRefreshAutomaticDownloads: FeedRefreshAutomaticDownloading {
    var episodesToReturn: [Episode]
    private(set) var refreshedSubscriptionIDs: Set<UUID> = []
    private(set) var failedSubscriptionIDs: Set<UUID> = []
    private(set) var limit: AutomaticDownloadLimit?
    private(set) var markedDownloadedEpisodes: [Episode] = []

    init(episodesToReturn: [Episode] = []) {
        self.episodesToReturn = episodesToReturn
    }

    func episodesToDownload(
        afterRefreshing refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>,
        subscriptions: [FeedSubscription],
        episodes: [Episode],
        downloadedEpisodeIDs: Set<AutomaticDownloadEpisodeID>,
        limit: AutomaticDownloadLimit
    ) async -> [Episode] {
        self.refreshedSubscriptionIDs = refreshedSubscriptionIDs
        self.failedSubscriptionIDs = failedSubscriptionIDs
        self.limit = limit
        return episodesToReturn
    }

    func markDownloaded(_ episodes: [Episode]) async {
        markedDownloadedEpisodes = episodes
    }
}

@MainActor
private final class StubFeedRefreshPreparation: FeedRefreshEpisodePreparing {
    var downloadedEpisodeIDs: Set<AutomaticDownloadEpisodeID> = []
    private let downloadedEpisodeIDsAfterPreparation: Set<String>
    private let insecurePermissionEpisodeIDs: Set<String>
    private(set) var preparedEpisodes: [Episode] = []

    init(
        downloadedEpisodeIDsAfterPreparation: Set<String> = [],
        insecurePermissionEpisodeIDs: Set<String> = []
    ) {
        self.downloadedEpisodeIDsAfterPreparation = downloadedEpisodeIDsAfterPreparation
        self.insecurePermissionEpisodeIDs = insecurePermissionEpisodeIDs
    }

    func prepare(_ episodes: [Episode], settings: AppSettings) async {
        preparedEpisodes = episodes
    }

    func downloadedRecord(for episode: Episode) -> DownloadedEpisodeRecord? {
        guard downloadedEpisodeIDsAfterPreparation.contains(episode.id),
              let subscriptionID = episode.subscriptionID else {
            return nil
        }
        return DownloadedEpisodeRecord(
            subscriptionID: subscriptionID,
            episodeID: episode.id,
            episodeTitle: episode.title,
            preparationAction: .passthroughMP3,
            downloadedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func requiresInsecureDownloadPermission(for episode: Episode) -> Bool {
        insecurePermissionEpisodeIDs.contains(episode.id)
    }
}
