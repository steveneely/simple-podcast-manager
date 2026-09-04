import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct PodcastRefreshCoordinatorTests {
    @Test
    func topLevelRefreshFailureIsAppliedToActivityAndAutomaticDownloads() async {
        let subscription = makeSubscription(number: 1)
        let episode = makeEpisode(number: 1, subscription: subscription)
        let summary = FeedSummary(subscriptionID: subscription.id, title: subscription.title)
        let preview = StubPodcastRefreshPreview(
            allEpisodes: [episode],
            feedSummaries: [subscription.id: summary],
            lastErrorMessage: "Network unavailable"
        )
        let activity = StubPodcastRefreshActivity()
        let automaticDownloads = StubPodcastRefreshAutomaticDownloads()
        let preparation = StubPodcastRefreshPreparation()
        let subscriptionLibrary = StubPodcastRefreshSubscriptionLibrary(
            podcastSubscriptions: [subscription],
            settings: AppSettings(automaticDownloadLimit: .latest1)
        )
        let coordinator = PodcastRefreshCoordinator(
            podcastPreview: preview,
            podcastLibrary: subscriptionLibrary,
            podcastActivity: activity,
            automaticDownloads: automaticDownloads,
            episodePreparation: preparation
        )

        let outcome = await coordinator.refresh(.allEnabledPodcasts([subscription]))

        #expect(preview.allSubscriptionsRefreshes == [[subscription]])
        #expect(activity.refreshedSubscriptionIDs == [subscription.id])
        #expect(activity.failedSubscriptionIDs == [subscription.id])
        #expect(automaticDownloads.refreshedSubscriptionIDs == [subscription.id])
        #expect(automaticDownloads.failedSubscriptionIDs == [subscription.id])
        #expect(automaticDownloads.limit == .latest1)
        #expect(subscriptionLibrary.appliedFeedSummaries == [summary])
        #expect(!outcome.attemptedAutomaticDownloads)
        #expect(outcome.discoveredEpisodeCount == 0)
        #expect(outcome.downloadedEpisodeCount == 0)
        #expect(outcome.downloadedEpisodes.isEmpty)
        #expect(outcome.failedSubscriptionCount == 1)
    }

    @Test
    func targetedRefreshPreparesEpisodesAndAcknowledgesOnlySuccessfulDownloads() async {
        let subscription = makeSubscription(number: 1)
        let unrelatedSubscription = makeSubscription(number: 2)
        let downloadedEpisode = makeEpisode(number: 1, subscription: subscription)
        let permissionEpisode = makeEpisode(number: 2, subscription: subscription)
        let preview = StubPodcastRefreshPreview(
            allEpisodes: [downloadedEpisode, permissionEpisode],
            failures: [FeedFetchFailure(
                subscriptionID: unrelatedSubscription.id,
                subscriptionTitle: unrelatedSubscription.title,
                message: "Unrelated failure"
            )]
        )
        let activity = StubPodcastRefreshActivity(discoveredEpisodeCount: 2)
        let automaticDownloads = StubPodcastRefreshAutomaticDownloads(
            episodesToReturn: [downloadedEpisode, permissionEpisode]
        )
        let preparation = StubPodcastRefreshPreparation(
            downloadedEpisodeIDsAfterPreparation: [downloadedEpisode.id],
            insecurePermissionEpisodeIDs: [permissionEpisode.id]
        )
        let subscriptionLibrary = StubPodcastRefreshSubscriptionLibrary(
            podcastSubscriptions: [subscription, unrelatedSubscription],
            settings: AppSettings(automaticDownloadLimit: .allNew)
        )
        let coordinator = PodcastRefreshCoordinator(
            podcastPreview: preview,
            podcastLibrary: subscriptionLibrary,
            podcastActivity: activity,
            automaticDownloads: automaticDownloads,
            episodePreparation: preparation
        )

        let outcome = await coordinator.refresh(.podcast(subscription))

        #expect(preview.subscriptionRefreshes == [subscription])
        #expect(activity.failedSubscriptionIDs.isEmpty)
        #expect(automaticDownloads.failedSubscriptionIDs.isEmpty)
        #expect(preparation.preparedEpisodes == [downloadedEpisode, permissionEpisode])
        #expect(automaticDownloads.markedDownloadedEpisodes == [downloadedEpisode])
        #expect(activity.acknowledgedEpisodes == [downloadedEpisode])
        #expect(outcome.episodesRequiringInsecureDownloadPermission == [permissionEpisode])
        #expect(outcome.attemptedAutomaticDownloads)
        #expect(outcome.discoveredEpisodeCount == 2)
        #expect(outcome.downloadedEpisodeCount == 1)
        #expect(outcome.downloadedEpisodes == [downloadedEpisode])
        #expect(outcome.failedSubscriptionCount == 0)
    }

    private func makeSubscription(number: Int) -> PodcastSubscription {
        PodcastSubscription(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
            title: "Podcast \(number)",
            rssURL: URL(string: "https://example.com/feed-\(number).xml")!
        )
    }

    private func makeEpisode(number: Int, subscription: PodcastSubscription) -> Episode {
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
private final class StubPodcastRefreshSubscriptionLibrary: PodcastRefreshLibraryUpdating {
    var podcastSubscriptions: [PodcastSubscription]
    var settings: AppSettings
    private(set) var appliedFeedSummaries: [FeedSummary] = []

    init(podcastSubscriptions: [PodcastSubscription], settings: AppSettings) {
        self.podcastSubscriptions = podcastSubscriptions
        self.settings = settings
    }

    func applyFeedSummaries(_ feedSummaries: [FeedSummary]) {
        appliedFeedSummaries = feedSummaries
    }
}

@MainActor
private final class StubPodcastRefreshPreview: PodcastRefreshPreviewing {
    var allEpisodes: [Episode]
    var failures: [FeedFetchFailure]
    var feedSummaries: [UUID: FeedSummary]
    var lastErrorMessage: String?
    private(set) var allSubscriptionsRefreshes: [[PodcastSubscription]] = []
    private(set) var subscriptionRefreshes: [PodcastSubscription] = []
    private(set) var newPodcastsRefreshes: [[PodcastSubscription]] = []

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

    func refreshPreview(for subscriptions: [PodcastSubscription]) async {
        allSubscriptionsRefreshes.append(subscriptions)
    }

    func refreshPreview(for subscription: PodcastSubscription) async {
        subscriptionRefreshes.append(subscription)
    }

    func refreshPreview(forNewSubscriptions subscriptions: [PodcastSubscription]) async {
        newPodcastsRefreshes.append(subscriptions)
    }
}

@MainActor
private final class StubPodcastRefreshActivity: PodcastRefreshActivityUpdating {
    let discoveredEpisodeCount: Int
    private(set) var refreshedSubscriptionIDs: Set<UUID> = []
    private(set) var failedSubscriptionIDs: Set<UUID> = []
    private(set) var acknowledgedEpisodes: [Episode] = []

    init(discoveredEpisodeCount: Int = 0) {
        self.discoveredEpisodeCount = discoveredEpisodeCount
    }

    func updateAfterRefresh(
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>
    ) async -> Int {
        self.refreshedSubscriptionIDs = refreshedSubscriptionIDs
        self.failedSubscriptionIDs = failedSubscriptionIDs
        return discoveredEpisodeCount
    }

    func acknowledge(_ episodes: [Episode]) async {
        acknowledgedEpisodes = episodes
    }
}

@MainActor
private final class StubPodcastRefreshAutomaticDownloads: PodcastRefreshAutomaticDownloading {
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
        subscriptions: [PodcastSubscription],
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
private final class StubPodcastRefreshPreparation: PodcastRefreshEpisodePreparing {
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

    func preparedEpisode(for episode: Episode) -> PreparedEpisode? {
        guard downloadedEpisodeIDsAfterPreparation.contains(episode.id) else { return nil }
        let fileURL = URL(fileURLWithPath: "/tmp/\(episode.id).mp3")
        return PreparedEpisode(
            episode: episode,
            sourceFileURL: fileURL,
            preparedFileURL: fileURL,
            preparationAction: .passthroughMP3
        )
    }

    func requiresInsecureDownloadPermission(for episode: Episode) -> Bool {
        insecurePermissionEpisodeIDs.contains(episode.id)
    }
}
