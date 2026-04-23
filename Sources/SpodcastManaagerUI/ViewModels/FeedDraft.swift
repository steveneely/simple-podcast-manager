import Foundation
import SpodcastManaagerCore

public enum FeedDraftError: Error, Equatable, Sendable {
    case invalidRSSURL
    case retentionMustBePositive
}

public struct FeedDraft: Equatable, Sendable {
    public var id: UUID?
    public var rssURLString: String
    public var artworkURL: URL?
    public var currentTitle: String?
    public var retentionEpisodeLimit: Int
    public var isEnabled: Bool

    public init(
        id: UUID? = nil,
        rssURLString: String = "",
        artworkURL: URL? = nil,
        currentTitle: String? = nil,
        retentionEpisodeLimit: Int = 3,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.rssURLString = rssURLString
        self.artworkURL = artworkURL
        self.currentTitle = currentTitle
        self.retentionEpisodeLimit = retentionEpisodeLimit
        self.isEnabled = isEnabled
    }

    public init(subscription: FeedSubscription) {
        self.id = subscription.id
        self.rssURLString = subscription.rssURL.absoluteString
        self.artworkURL = subscription.artworkURL
        self.currentTitle = subscription.title
        self.retentionEpisodeLimit = subscription.retentionPolicy.episodeLimit
        self.isEnabled = subscription.isEnabled
    }

    public var canSave: Bool {
        let normalizedURLString = rssURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = URL(string: normalizedURLString)?.scheme?.lowercased()

        return (scheme == "http" || scheme == "https")
            && retentionEpisodeLimit > 0
    }

    public func resolvedRSSURL() throws -> URL {
        guard retentionEpisodeLimit > 0 else {
            throw FeedDraftError.retentionMustBePositive
        }

        guard
            let rssURL = URL(string: rssURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = rssURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            throw FeedDraftError.invalidRSSURL
        }

        return rssURL
    }

    public func makeSubscription(title: String, artworkURL: URL?) throws -> FeedSubscription {
        return FeedSubscription(
            id: id ?? UUID(),
            title: title,
            rssURL: try resolvedRSSURL(),
            artworkURL: artworkURL,
            retentionPolicy: .keepLatestEpisodes(retentionEpisodeLimit),
            isEnabled: isEnabled
        )
    }
}
