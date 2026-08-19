import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class MainViewModel {
    public private(set) var feedSubscriptions: [FeedSubscription]
    public private(set) var settings: AppSettings
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedConfiguration: Bool

    private let store: any ConfigurationStore
    private let feedResolver: any FeedResolving
    private let feedCacheStore: any FeedCacheStore

    public init(
        store: any ConfigurationStore,
        feedResolver: any FeedResolving = RSSFeedResolutionService(),
        feedCacheStore: any FeedCacheStore = JSONFeedCacheStore(directoryURL: JSONFeedCacheStore.defaultDirectoryURL())
    ) {
        self.store = store
        self.feedResolver = feedResolver
        self.feedCacheStore = feedCacheStore
        self.feedSubscriptions = []
        self.settings = AppSettings()
        self.lastErrorMessage = nil
        self.hasLoadedConfiguration = false
    }

    public var hasFeeds: Bool {
        !feedSubscriptions.isEmpty
    }

    public func load() {
        do {
            let configuration = try store.loadConfiguration()
            self.feedSubscriptions = configuration.feedSubscriptions.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            self.settings = configuration.settings
            self.lastErrorMessage = nil
            self.hasLoadedConfiguration = true
        } catch {
            self.lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func addFeed(from draft: FeedDraft) throws -> FeedSubscription.ID {
        do {
            let rssURL = try draft.resolvedRSSURL()
            let subscription = try draft.makeSubscription(
                title: provisionalTitle(for: rssURL),
                artworkURL: draft.artworkURL,
                description: nil
            )
            return try addSubscriptions([subscription])[0]
        } catch {
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    public func updateFeed(from draft: FeedDraft) async throws {
        do {
            let rssURL = try draft.resolvedRSSURL()
            if let subscriptionID = draft.id,
               let existingSubscription = feedSubscriptions.first(where: { $0.id == subscriptionID }),
               rssURL == existingSubscription.rssURL {
                let updatedSubscription = try draft.makeSubscription(
                    title: existingSubscription.title,
                    artworkURL: existingSubscription.artworkURL,
                    description: existingSubscription.description
                )
                try saveUpdatedSubscription(updatedSubscription)
                return
            }

            let resolvedFeed = try await resolveFeed(from: draft)
            try saveUpdatedSubscription(resolvedFeed.subscription)
            try? feedCacheStore.saveCachedFeed(resolvedFeed.cachedFeed)
        } catch {
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    public func removeFeeds(at offsets: IndexSet) {
        let removedIDs = offsets.compactMap { offset in
            feedSubscriptions.indices.contains(offset) ? feedSubscriptions[offset].id : nil
        }
        let removedIDSet = Set(removedIDs)
        mutateConfiguration {
            $0.feedSubscriptions.removeAll { removedIDSet.contains($0.id) }
        }

        for removedID in removedIDs {
            try? feedCacheStore.deleteCachedFeed(for: removedID)
        }
    }

    public func replaceSettings(_ settings: AppSettings) {
        mutateConfiguration {
            $0.settings = settings
        }
    }

    @discardableResult
    public func importSubscriptions(_ subscriptions: [OPMLSubscription]) throws -> [FeedSubscription.ID] {
        let feedSubscriptions = subscriptions.map {
            FeedSubscription(title: $0.title, rssURL: $0.rssURL)
        }
        return try addSubscriptions(feedSubscriptions)
    }

    public func applyFeedSummaries(_ feedSummaries: [FeedSummary]) {
        guard !feedSummaries.isEmpty else { return }
        let summariesByID = Dictionary(uniqueKeysWithValues: feedSummaries.map { ($0.subscriptionID, $0) })

        let needsUpdate = feedSubscriptions.contains { subscription in
            guard let summary = summariesByID[subscription.id] else { return false }
            return subscription.title != summary.title
                || subscription.artworkURL != summary.artworkURL
                || subscription.description != summary.description
        }
        guard needsUpdate else { return }

        mutateConfiguration {
            for index in $0.feedSubscriptions.indices {
                let subscriptionID = $0.feedSubscriptions[index].id
                guard let summary = summariesByID[subscriptionID] else { continue }

                if $0.feedSubscriptions[index].title != summary.title {
                    $0.feedSubscriptions[index].title = summary.title
                }

                if $0.feedSubscriptions[index].artworkURL != summary.artworkURL {
                    $0.feedSubscriptions[index].artworkURL = summary.artworkURL
                }

                if $0.feedSubscriptions[index].description != summary.description {
                    $0.feedSubscriptions[index].description = summary.description
                }
            }
            $0.feedSubscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private func mutateConfiguration(_ transform: (inout AppConfiguration) throws -> Void) {
        do {
            try commitConfiguration(transform)
        } catch {
            self.lastErrorMessage = error.localizedDescription
        }
    }

    private func commitConfiguration(_ transform: (inout AppConfiguration) throws -> Void) throws {
        var configuration = try store.loadConfiguration()
        try transform(&configuration)
        try store.saveConfiguration(configuration)

        self.feedSubscriptions = configuration.feedSubscriptions.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        self.settings = configuration.settings
        self.lastErrorMessage = nil
        self.hasLoadedConfiguration = true
    }

    private func ensureUniqueSubscription(
        _ subscription: FeedSubscription,
        in existingSubscriptions: [FeedSubscription],
        excluding excludedID: FeedSubscription.ID? = nil
    ) throws {
        let normalizedURL = subscription.rssURL.absoluteString.lowercased()
        if existingSubscriptions.contains(where: {
            $0.id != excludedID && $0.rssURL.absoluteString.lowercased() == normalizedURL
        }) {
            throw MainViewModelError.duplicateSubscription
        }
    }

    private func addSubscriptions(_ subscriptions: [FeedSubscription]) throws -> [FeedSubscription.ID] {
        guard !subscriptions.isEmpty else { return [] }

        do {
            try commitConfiguration {
                for subscription in subscriptions {
                    try ensureUniqueSubscription(subscription, in: $0.feedSubscriptions)
                    $0.feedSubscriptions.append(subscription)
                }
                $0.feedSubscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }
            return subscriptions.map(\.id)
        } catch {
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func resolveFeed(from draft: FeedDraft) async throws -> (subscription: FeedSubscription, cachedFeed: CachedFeed) {
        let rssURL = try draft.resolvedRSSURL()
        let subscriptionID = draft.id ?? UUID()
        var cachedFeed = try await feedResolver.resolveFeed(for: rssURL, subscriptionID: subscriptionID)

        var resolvedDraft = draft
        resolvedDraft.id = subscriptionID
        let subscription = try resolvedDraft.makeSubscription(
            title: cachedFeed.summary.title,
            artworkURL: cachedFeed.summary.artworkURL ?? draft.artworkURL,
            description: cachedFeed.summary.description
        )
        cachedFeed.summary = FeedSummary(
            subscriptionID: subscription.id,
            title: subscription.title,
            artworkURL: subscription.artworkURL,
            description: subscription.description
        )
        return (subscription, cachedFeed)
    }

    private func saveUpdatedSubscription(_ updatedSubscription: FeedSubscription) throws {
        try commitConfiguration {
            try ensureUniqueSubscription(
                updatedSubscription,
                in: $0.feedSubscriptions,
                excluding: updatedSubscription.id
            )
            guard let existingIndex = $0.feedSubscriptions.firstIndex(where: { $0.id == updatedSubscription.id }) else {
                $0.feedSubscriptions.append(updatedSubscription)
                $0.feedSubscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                return
            }

            $0.feedSubscriptions[existingIndex] = updatedSubscription
            $0.feedSubscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private func provisionalTitle(for rssURL: URL) -> String {
        guard let host = rssURL.host(percentEncoded: false), !host.isEmpty else {
            return rssURL.absoluteString
        }

        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

public enum MainViewModelError: LocalizedError, Equatable, Sendable {
    case duplicateSubscription

    public var errorDescription: String? {
        switch self {
        case .duplicateSubscription:
            return "That podcast feed is already in your subscription list."
        }
    }
}
