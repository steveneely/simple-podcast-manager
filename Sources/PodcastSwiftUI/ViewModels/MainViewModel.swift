import Foundation
import Observation
import PodcastSwiftCore

@MainActor
@Observable
public final class MainViewModel {
    public private(set) var feedSubscriptions: [FeedSubscription]
    public private(set) var settings: AppSettings
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedConfiguration: Bool

    private let store: any ConfigurationStore

    public init(store: any ConfigurationStore) {
        self.store = store
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

    public func addFeed(from draft: FeedDraft) {
        mutateConfiguration {
            let subscription = try draft.makeSubscription()
            try ensureUniqueSubscription(subscription, in: $0.feedSubscriptions)
            $0.feedSubscriptions.append(subscription)
            $0.feedSubscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    public func addFeed(from discoveryResult: DiscoveryResult, defaultRetentionEpisodeLimit: Int = 3) {
        mutateConfiguration {
            let subscription = try discoveryResult.makeSubscription(defaultRetentionEpisodeLimit: defaultRetentionEpisodeLimit)
            try ensureUniqueSubscription(subscription, in: $0.feedSubscriptions)
            $0.feedSubscriptions.append(subscription)
            $0.feedSubscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    public func updateFeed(from draft: FeedDraft) {
        mutateConfiguration {
            let updatedSubscription = try draft.makeSubscription()
            try ensureUniqueSubscription(updatedSubscription, in: $0.feedSubscriptions, excluding: updatedSubscription.id)
            guard let existingIndex = $0.feedSubscriptions.firstIndex(where: { $0.id == updatedSubscription.id }) else {
                $0.feedSubscriptions.append(updatedSubscription)
                $0.feedSubscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                return
            }

            $0.feedSubscriptions[existingIndex] = updatedSubscription
            $0.feedSubscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    public func removeFeeds(at offsets: IndexSet) {
        mutateConfiguration {
            for index in offsets.sorted(by: >) {
                $0.feedSubscriptions.remove(at: index)
            }
        }
    }

    public func setDryRunByDefault(_ value: Bool) {
        mutateConfiguration {
            $0.settings.dryRunByDefault = value
        }
    }

    public func setEjectAfterSyncByDefault(_ value: Bool) {
        mutateConfiguration {
            $0.settings.ejectAfterSyncByDefault = value
        }
    }

    public func setFFmpegExecutablePath(_ value: String?) {
        mutateConfiguration {
            let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.settings.ffmpegExecutablePath = (trimmedValue?.isEmpty == false) ? trimmedValue : nil
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

    private func mutateConfiguration(_ transform: (inout AppConfiguration) throws -> Void) {
        do {
            var configuration = try store.loadConfiguration()
            try transform(&configuration)
            try store.saveConfiguration(configuration)

            self.feedSubscriptions = configuration.feedSubscriptions.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            self.settings = configuration.settings
            self.lastErrorMessage = nil
            self.hasLoadedConfiguration = true
        } catch {
            self.lastErrorMessage = error.localizedDescription
        }
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
