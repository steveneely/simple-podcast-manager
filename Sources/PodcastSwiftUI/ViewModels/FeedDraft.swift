import Foundation
import PodcastSwiftCore

public enum FeedDraftError: Error, Equatable, Sendable {
    case emptyTitle
    case invalidRSSURL
    case retentionMustBePositive
}

public struct FeedDraft: Equatable, Sendable {
    public var id: UUID?
    public var title: String
    public var rssURLString: String
    public var artworkURL: URL?
    public var podcastFolderName: String
    public var retentionEpisodeLimit: Int
    public var isEnabled: Bool

    public init(
        id: UUID? = nil,
        title: String = "",
        rssURLString: String = "",
        artworkURL: URL? = nil,
        podcastFolderName: String = "",
        retentionEpisodeLimit: Int = 3,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.rssURLString = rssURLString
        self.artworkURL = artworkURL
        self.podcastFolderName = podcastFolderName
        self.retentionEpisodeLimit = retentionEpisodeLimit
        self.isEnabled = isEnabled
    }

    public init(subscription: FeedSubscription) {
        self.id = subscription.id
        self.title = subscription.title
        self.rssURLString = subscription.rssURL.absoluteString
        self.artworkURL = subscription.artworkURL
        self.podcastFolderName = subscription.podcastFolderName ?? ""
        self.retentionEpisodeLimit = subscription.retentionPolicy.episodeLimit
        self.isEnabled = subscription.isEnabled
    }

    public var canSave: Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURLString = rssURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = URL(string: normalizedURLString)?.scheme?.lowercased()

        return !normalizedTitle.isEmpty
            && (scheme == "http" || scheme == "https")
            && retentionEpisodeLimit > 0
    }

    public func makeSubscription() throws -> FeedSubscription {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw FeedDraftError.emptyTitle
        }

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

        let folderName = podcastFolderName.trimmingCharacters(in: .whitespacesAndNewlines)

        return FeedSubscription(
            id: id ?? UUID(),
            title: normalizedTitle,
            rssURL: rssURL,
            artworkURL: artworkURL,
            podcastFolderName: folderName.isEmpty ? nil : folderName,
            retentionPolicy: .keepLatestEpisodes(retentionEpisodeLimit),
            isEnabled: isEnabled
        )
    }
}
