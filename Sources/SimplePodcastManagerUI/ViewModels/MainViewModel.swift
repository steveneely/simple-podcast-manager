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
    private let metadataResolver: any FeedMetadataResolving
    private let feedCacheStore: any FeedCacheStore

    public init(
        store: any ConfigurationStore,
        metadataResolver: any FeedMetadataResolving = RSSFeedMetadataService(),
        feedCacheStore: any FeedCacheStore = JSONFeedCacheStore(directoryURL: JSONFeedCacheStore.defaultDirectoryURL())
    ) {
        self.store = store
        self.metadataResolver = metadataResolver
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

    public func addFeed(from draft: FeedDraft) async throws {
        do {
            let rssURL = try draft.resolvedRSSURL()
            let summary = try await metadataResolver.resolveMetadata(for: rssURL, subscriptionID: draft.id)
            try commitConfiguration {
                let subscription = try draft.makeSubscription(
                    title: summary.title,
                    artworkURL: summary.artworkURL ?? draft.artworkURL,
                    description: summary.description
                )
                try ensureUniqueSubscription(subscription, in: $0.feedSubscriptions)
                $0.feedSubscriptions.append(subscription)
                $0.feedSubscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }
        } catch {
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    public func updateFeed(from draft: FeedDraft) async throws {
        do {
            let rssURL = try draft.resolvedRSSURL()
            let summary = try await metadataResolver.resolveMetadata(for: rssURL, subscriptionID: draft.id)
            let previousSubscription = feedSubscriptions.first { $0.id == draft.id }
            try commitConfiguration {
                let updatedSubscription = try draft.makeSubscription(
                    title: summary.title,
                    artworkURL: summary.artworkURL ?? draft.artworkURL,
                    description: summary.description
                )
                try ensureUniqueSubscription(updatedSubscription, in: $0.feedSubscriptions, excluding: updatedSubscription.id)
                guard let existingIndex = $0.feedSubscriptions.firstIndex(where: { $0.id == updatedSubscription.id }) else {
                    $0.feedSubscriptions.append(updatedSubscription)
                    $0.feedSubscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    return
                }

                $0.feedSubscriptions[existingIndex] = updatedSubscription
                $0.feedSubscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }

            if let previousSubscription, previousSubscription.rssURL != rssURL {
                try? feedCacheStore.deleteCachedFeed(for: previousSubscription.id)
            }
        } catch {
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    public func removeFeeds(at offsets: IndexSet) {
        let removedIDs = offsets.compactMap { offset in
            feedSubscriptions.indices.contains(offset) ? feedSubscriptions[offset].id : nil
        }
        mutateConfiguration {
            for index in offsets.sorted(by: >) {
                $0.feedSubscriptions.remove(at: index)
            }
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

    public func clearLastError() {
        lastErrorMessage = nil
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
