import Foundation
import Observation
import SPodcastManagerCore

@MainActor
@Observable
public final class FeedPreviewViewModel {
    public private(set) var allEpisodes: [Episode]
    public private(set) var selectedEpisodes: [Episode]
    public private(set) var failures: [FeedFetchFailure]
    public private(set) var feedSummaries: [UUID: FeedSummary]
    public private(set) var isLoading: Bool
    public private(set) var lastErrorMessage: String?

    private let service: any FeedService

    public init(service: any FeedService = RSSFeedService()) {
        self.service = service
        self.allEpisodes = []
        self.selectedEpisodes = []
        self.failures = []
        self.feedSummaries = [:]
        self.isLoading = false
        self.lastErrorMessage = nil
    }

    public var hasPreviewData: Bool {
        !allEpisodes.isEmpty || !selectedEpisodes.isEmpty || !failures.isEmpty || !feedSummaries.isEmpty
    }

    public func refreshPreview(for subscriptions: [FeedSubscription]) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await service.fetchLatestEpisodes(for: subscriptions)
            self.allEpisodes = result.allEpisodes
            self.selectedEpisodes = result.selectedEpisodes
            self.failures = result.failures
            self.feedSummaries = Dictionary(uniqueKeysWithValues: result.feedSummaries.map { ($0.subscriptionID, $0) })
            self.lastErrorMessage = nil
        } catch {
            self.allEpisodes = []
            self.selectedEpisodes = []
            self.failures = []
            self.feedSummaries = [:]
            self.lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func artworkURL(for subscriptionID: UUID) -> URL? {
        feedSummaries[subscriptionID]?.artworkURL
    }
}
