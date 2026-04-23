import Foundation
import FeedKit

public final class RSSFeedParser: Sendable {
    public init() {}

    public func parse(data: Data, sourceFeedURL: URL, subscriptionID: UUID?) throws -> ParsedRSSFeed {
        let parsedFeed: Feed
        do {
            parsedFeed = try Feed(data: data)
        } catch {
            throw FeedServiceError.invalidFeedData
        }

        switch parsedFeed {
        case .rss(let rssFeed):
            return Self.makeParsedRSSFeed(from: rssFeed, sourceFeedURL: sourceFeedURL, subscriptionID: subscriptionID)
        default:
            throw FeedServiceError.invalidFeedData
        }
    }
}

public struct ParsedRSSFeed: Equatable, Sendable {
    public var title: String
    public var artworkURL: URL?
    public var episodes: [Episode]

    public init(title: String, artworkURL: URL? = nil, episodes: [Episode]) {
        self.title = title
        self.artworkURL = artworkURL
        self.episodes = episodes
    }
}

private extension RSSFeedParser {
    static func makeParsedRSSFeed(from feed: RSSFeed, sourceFeedURL: URL, subscriptionID: UUID?) -> ParsedRSSFeed {
        let feedTitle = feed.channel?.title ?? sourceFeedURL.absoluteString
        let artworkURL = channelArtworkURL(from: feed.channel)
        let episodes = (feed.channel?.items ?? []).compactMap {
            makeEpisode(from: $0, feedTitle: feedTitle, sourceFeedURL: sourceFeedURL, subscriptionID: subscriptionID)
        }

        return ParsedRSSFeed(
            title: feedTitle,
            artworkURL: artworkURL,
            episodes: episodes
        )
    }

    static func channelArtworkURL(from channel: RSSFeedChannel?) -> URL? {
        if let href = channel?.iTunes?.image?.attributes?.href {
            return URL(string: href)
        }

        if let imageURL = channel?.image?.url {
            return URL(string: imageURL)
        }

        return nil
    }

    static func makeEpisode(
        from item: RSSFeedItem,
        feedTitle: String,
        sourceFeedURL: URL,
        subscriptionID: UUID?
    ) -> Episode? {
        let resolvedURLString = normalizedEnclosureURL(from: item.enclosure?.attributes?.url)
            ?? fallbackEmbedURLString(from: item)

        guard
            let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty,
            let resolvedURLString,
            let enclosureURL = URL(string: resolvedURLString)
        else {
            return nil
        }

        let episodeID = item.guid?.text ?? enclosureURL.absoluteString

        return Episode(
            id: episodeID,
            subscriptionID: subscriptionID,
            podcastTitle: feedTitle,
            title: title,
            publicationDate: item.pubDate,
            enclosureURL: enclosureURL,
            sourceFeedURL: sourceFeedURL
        )
    }

    static func normalizedEnclosureURL(from enclosureURL: String?) -> String? {
        guard let enclosureURL = enclosureURL?.trimmingCharacters(in: .whitespacesAndNewlines), !enclosureURL.isEmpty else {
            return nil
        }

        return enclosureURL
    }

    static func fallbackEmbedURLString(from item: RSSFeedItem) -> String? {
        [item.content?.encoded, item.iTunes?.summary, item.description]
            .compactMap(Self.extractTransistorEmbedURL(from:))
            .first
    }

    static func extractTransistorEmbedURL(from text: String?) -> String? {
        guard let text, !text.isEmpty else {
            return nil
        }

        let pattern = #"https://share\.transistor\.fm/e/[A-Za-z0-9]+(?:/[^\s"'<>]*)?"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: []),
            let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range, in: text)
        else {
            return nil
        }

        return text[range]
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
