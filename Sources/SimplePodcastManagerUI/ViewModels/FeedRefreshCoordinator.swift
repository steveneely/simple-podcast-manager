import Foundation
import SimplePodcastManagerCore

enum FeedRefreshScope {
    case allEnabledSubscriptions([FeedSubscription])
    case subscription(FeedSubscription)
    case newSubscriptions([FeedSubscription])

    var subscriptions: [FeedSubscription] {
        switch self {
        case let .allEnabledSubscriptions(subscriptions), let .newSubscriptions(subscriptions):
            subscriptions
        case let .subscription(subscription):
            [subscription]
        }
    }
}

struct FeedRefreshOutcome {
    var episodesRequiringInsecureDownloadPermission: [Episode]
    var attemptedAutomaticDownloads: Bool
}

@MainActor
final class FeedRefreshCoordinator {
    private let feedPreview: any FeedRefreshPreviewing
    private let subscriptionLibrary: any FeedRefreshSubscriptionUpdating
    private let feedActivity: any FeedRefreshActivityUpdating
    private let automaticDownloads: any FeedRefreshAutomaticDownloading
    private let episodePreparation: any FeedRefreshEpisodePreparing

    init(
        feedPreview: any FeedRefreshPreviewing,
        subscriptionLibrary: any FeedRefreshSubscriptionUpdating,
        feedActivity: any FeedRefreshActivityUpdating,
        automaticDownloads: any FeedRefreshAutomaticDownloading,
        episodePreparation: any FeedRefreshEpisodePreparing
    ) {
        self.feedPreview = feedPreview
        self.subscriptionLibrary = subscriptionLibrary
        self.feedActivity = feedActivity
        self.automaticDownloads = automaticDownloads
        self.episodePreparation = episodePreparation
    }

    func refresh(
        _ scope: FeedRefreshScope,
        openSubscriptionID: UUID?
    ) async -> FeedRefreshOutcome {
        await refreshPreview(for: scope)
        subscriptionLibrary.applyFeedSummaries(Array(feedPreview.feedSummaries.values))

        let refreshedSubscriptionIDs = Set(scope.subscriptions.filter(\.isEnabled).map(\.id))
        let failedSubscriptionIDs = failedSubscriptionIDs(in: refreshedSubscriptionIDs)
        await feedActivity.updateAfterRefresh(
            subscriptions: subscriptionLibrary.feedSubscriptions,
            episodes: feedPreview.allEpisodes,
            refreshedSubscriptionIDs: refreshedSubscriptionIDs,
            failedSubscriptionIDs: failedSubscriptionIDs,
            openSubscriptionID: openSubscriptionID
        )

        let episodesToDownload = await automaticDownloads.episodesToDownload(
            afterRefreshing: refreshedSubscriptionIDs,
            failedSubscriptionIDs: failedSubscriptionIDs,
            subscriptions: subscriptionLibrary.feedSubscriptions,
            episodes: feedPreview.allEpisodes,
            downloadedEpisodeIDs: episodePreparation.downloadedEpisodeIDs,
            limit: subscriptionLibrary.settings.automaticDownloadLimit
        )
        guard !episodesToDownload.isEmpty else {
            return FeedRefreshOutcome(
                episodesRequiringInsecureDownloadPermission: [],
                attemptedAutomaticDownloads: false
            )
        }

        await episodePreparation.prepare(episodesToDownload, settings: subscriptionLibrary.settings)
        await automaticDownloads.markDownloaded(episodesToDownload.filter {
            episodePreparation.downloadedRecord(for: $0) != nil
        })

        return FeedRefreshOutcome(
            episodesRequiringInsecureDownloadPermission: episodesToDownload.filter {
                episodePreparation.requiresInsecureDownloadPermission(for: $0)
            },
            attemptedAutomaticDownloads: true
        )
    }

    private func refreshPreview(for scope: FeedRefreshScope) async {
        switch scope {
        case let .allEnabledSubscriptions(subscriptions):
            await feedPreview.refreshPreview(for: subscriptions)
        case let .subscription(subscription):
            await feedPreview.refreshPreview(for: subscription)
        case let .newSubscriptions(subscriptions):
            await feedPreview.refreshPreview(forNewSubscriptions: subscriptions)
        }
    }

    private func failedSubscriptionIDs(in refreshedSubscriptionIDs: Set<UUID>) -> Set<UUID> {
        if feedPreview.lastErrorMessage != nil {
            return refreshedSubscriptionIDs
        }

        return Set(feedPreview.failures.compactMap { failure in
            refreshedSubscriptionIDs.contains(failure.subscriptionID) ? failure.subscriptionID : nil
        })
    }
}

@MainActor
protocol FeedRefreshSubscriptionUpdating: AnyObject {
    var feedSubscriptions: [FeedSubscription] { get }
    var settings: AppSettings { get }

    func applyFeedSummaries(_ feedSummaries: [FeedSummary])
}

@MainActor
protocol FeedRefreshPreviewing: AnyObject {
    var allEpisodes: [Episode] { get }
    var failures: [FeedFetchFailure] { get }
    var feedSummaries: [UUID: FeedSummary] { get }
    var lastErrorMessage: String? { get }

    func refreshPreview(for subscriptions: [FeedSubscription]) async
    func refreshPreview(for subscription: FeedSubscription) async
    func refreshPreview(forNewSubscriptions subscriptions: [FeedSubscription]) async
}

@MainActor
protocol FeedRefreshActivityUpdating: AnyObject {
    func updateAfterRefresh(
        subscriptions: [FeedSubscription],
        episodes: [Episode],
        refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>,
        openSubscriptionID: UUID?
    ) async
}

@MainActor
protocol FeedRefreshAutomaticDownloading: AnyObject {
    func episodesToDownload(
        afterRefreshing refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>,
        subscriptions: [FeedSubscription],
        episodes: [Episode],
        downloadedEpisodeIDs: Set<AutomaticDownloadEpisodeID>,
        limit: AutomaticDownloadLimit
    ) async -> [Episode]

    func markDownloaded(_ episodes: [Episode]) async
}

@MainActor
protocol FeedRefreshEpisodePreparing: AnyObject {
    var downloadedEpisodeIDs: Set<AutomaticDownloadEpisodeID> { get }

    func prepare(_ episodes: [Episode], settings: AppSettings) async
    func downloadedRecord(for episode: Episode) -> DownloadedEpisodeRecord?
    func requiresInsecureDownloadPermission(for episode: Episode) -> Bool
}

extension FeedPreviewViewModel: FeedRefreshPreviewing {}
extension MainViewModel: FeedRefreshSubscriptionUpdating {}
extension FeedActivityViewModel: FeedRefreshActivityUpdating {}
extension AutomaticDownloadViewModel: FeedRefreshAutomaticDownloading {}
extension PreparationPreviewViewModel: FeedRefreshEpisodePreparing {}
