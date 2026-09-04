import Foundation
import SimplePodcastManagerCore

enum PodcastRefreshScope {
    case allEnabledPodcasts([PodcastSubscription])
    case podcast(PodcastSubscription)
    case newPodcasts([PodcastSubscription])

    var podcasts: [PodcastSubscription] {
        switch self {
        case let .allEnabledPodcasts(podcasts), let .newPodcasts(podcasts):
            podcasts
        case let .podcast(podcast):
            [podcast]
        }
    }
}

struct PodcastRefreshOutcome {
    var episodesRequiringInsecureDownloadPermission: [Episode]
    var attemptedAutomaticDownloads: Bool
    var discoveredEpisodeCount: Int
    var downloadedEpisodes: [Episode]
    var failedSubscriptionCount: Int

    var downloadedEpisodeCount: Int { downloadedEpisodes.count }
}

@MainActor
final class PodcastRefreshCoordinator {
    private let podcastPreview: any PodcastRefreshPreviewing
    private let podcastLibrary: any PodcastRefreshLibraryUpdating
    private let podcastActivity: any PodcastRefreshActivityUpdating
    private let automaticDownloads: any PodcastRefreshAutomaticDownloading
    private let episodePreparation: any PodcastRefreshEpisodePreparing

    init(
        podcastPreview: any PodcastRefreshPreviewing,
        podcastLibrary: any PodcastRefreshLibraryUpdating,
        podcastActivity: any PodcastRefreshActivityUpdating,
        automaticDownloads: any PodcastRefreshAutomaticDownloading,
        episodePreparation: any PodcastRefreshEpisodePreparing
    ) {
        self.podcastPreview = podcastPreview
        self.podcastLibrary = podcastLibrary
        self.podcastActivity = podcastActivity
        self.automaticDownloads = automaticDownloads
        self.episodePreparation = episodePreparation
    }

    func refresh(_ scope: PodcastRefreshScope) async -> PodcastRefreshOutcome {
        await refreshPreview(for: scope)
        podcastLibrary.applyFeedSummaries(Array(podcastPreview.feedSummaries.values))

        let refreshedSubscriptionIDs = Set(scope.podcasts.filter(\.isEnabled).map(\.id))
        let failedSubscriptionIDs = failedSubscriptionIDs(in: refreshedSubscriptionIDs)
        let discoveredEpisodeCount = await podcastActivity.updateAfterRefresh(
            subscriptions: podcastLibrary.podcastSubscriptions,
            episodes: podcastPreview.allEpisodes,
            refreshedSubscriptionIDs: refreshedSubscriptionIDs,
            failedSubscriptionIDs: failedSubscriptionIDs
        )

        let episodesToDownload = await automaticDownloads.episodesToDownload(
            afterRefreshing: refreshedSubscriptionIDs,
            failedSubscriptionIDs: failedSubscriptionIDs,
            subscriptions: podcastLibrary.podcastSubscriptions,
            episodes: podcastPreview.allEpisodes,
            downloadedEpisodeIDs: episodePreparation.downloadedEpisodeIDs,
            limit: podcastLibrary.settings.automaticDownloadLimit
        )
        guard !episodesToDownload.isEmpty else {
            return PodcastRefreshOutcome(
                episodesRequiringInsecureDownloadPermission: [],
                attemptedAutomaticDownloads: false,
                discoveredEpisodeCount: discoveredEpisodeCount,
                downloadedEpisodes: [],
                failedSubscriptionCount: failedSubscriptionIDs.count
            )
        }

        await episodePreparation.prepare(episodesToDownload, settings: podcastLibrary.settings)
        let downloadedEpisodes = episodesToDownload.filter {
            episodePreparation.preparedEpisode(for: $0) != nil
        }
        await automaticDownloads.markDownloaded(downloadedEpisodes)
        await podcastActivity.acknowledge(downloadedEpisodes)

        return PodcastRefreshOutcome(
            episodesRequiringInsecureDownloadPermission: episodesToDownload.filter {
                episodePreparation.requiresInsecureDownloadPermission(for: $0)
            },
            attemptedAutomaticDownloads: true,
            discoveredEpisodeCount: discoveredEpisodeCount,
            downloadedEpisodes: downloadedEpisodes,
            failedSubscriptionCount: failedSubscriptionIDs.count
        )
    }

    private func refreshPreview(for scope: PodcastRefreshScope) async {
        switch scope {
        case let .allEnabledPodcasts(podcasts):
            await podcastPreview.refreshPreview(for: podcasts)
        case let .podcast(podcast):
            await podcastPreview.refreshPreview(for: podcast)
        case let .newPodcasts(podcasts):
            await podcastPreview.refreshPreview(forNewSubscriptions: podcasts)
        }
    }

    private func failedSubscriptionIDs(in refreshedSubscriptionIDs: Set<UUID>) -> Set<UUID> {
        if podcastPreview.lastErrorMessage != nil {
            return refreshedSubscriptionIDs
        }

        return Set(podcastPreview.failures.compactMap { failure in
            refreshedSubscriptionIDs.contains(failure.subscriptionID) ? failure.subscriptionID : nil
        })
    }
}

@MainActor
protocol PodcastRefreshLibraryUpdating: AnyObject {
    var podcastSubscriptions: [PodcastSubscription] { get }
    var settings: AppSettings { get }

    func applyFeedSummaries(_ feedSummaries: [FeedSummary])
}

@MainActor
protocol PodcastRefreshPreviewing: AnyObject {
    var allEpisodes: [Episode] { get }
    var failures: [FeedFetchFailure] { get }
    var feedSummaries: [UUID: FeedSummary] { get }
    var lastErrorMessage: String? { get }

    func refreshPreview(for subscriptions: [PodcastSubscription]) async
    func refreshPreview(for subscription: PodcastSubscription) async
    func refreshPreview(forNewSubscriptions subscriptions: [PodcastSubscription]) async
}

@MainActor
protocol PodcastRefreshActivityUpdating: AnyObject {
    func updateAfterRefresh(
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>
    ) async -> Int

    func acknowledge(_ episodes: [Episode]) async
}

@MainActor
protocol PodcastRefreshAutomaticDownloading: AnyObject {
    func episodesToDownload(
        afterRefreshing refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>,
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        downloadedEpisodeIDs: Set<AutomaticDownloadEpisodeID>,
        limit: AutomaticDownloadLimit
    ) async -> [Episode]

    func markDownloaded(_ episodes: [Episode]) async
}

@MainActor
protocol PodcastRefreshEpisodePreparing: AnyObject {
    var downloadedEpisodeIDs: Set<AutomaticDownloadEpisodeID> { get }

    func prepare(_ episodes: [Episode], settings: AppSettings) async
    func preparedEpisode(for episode: Episode) -> PreparedEpisode?
    func requiresInsecureDownloadPermission(for episode: Episode) -> Bool
}

extension PodcastPreviewViewModel: PodcastRefreshPreviewing {}
extension MainViewModel: PodcastRefreshLibraryUpdating {}
extension PodcastActivityViewModel: PodcastRefreshActivityUpdating {}
extension AutomaticDownloadViewModel: PodcastRefreshAutomaticDownloading {}
extension PreparationPreviewViewModel: PodcastRefreshEpisodePreparing {}
