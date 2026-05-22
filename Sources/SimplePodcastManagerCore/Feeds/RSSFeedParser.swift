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
    public var description: String?
    public var episodes: [Episode]

    public init(title: String, artworkURL: URL? = nil, description: String? = nil, episodes: [Episode]) {
        self.title = title
        self.artworkURL = artworkURL
        self.description = description
        self.episodes = episodes
    }
}

private extension RSSFeedParser {
    static func makeParsedRSSFeed(from feed: RSSFeed, sourceFeedURL: URL, subscriptionID: UUID?) -> ParsedRSSFeed {
        let feedTitle = feed.channel?.title ?? sourceFeedURL.absoluteString
        let artworkURL = channelArtworkURL(from: feed.channel)
        let description = channelDescription(from: feed.channel)
        let episodes = (feed.channel?.items ?? []).compactMap {
            makeEpisode(from: $0, feedTitle: feedTitle, sourceFeedURL: sourceFeedURL, subscriptionID: subscriptionID)
        }

        return ParsedRSSFeed(
            title: feedTitle,
            artworkURL: artworkURL,
            description: description,
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

    static func channelDescription(from channel: RSSFeedChannel?) -> String? {
        [channel?.iTunes?.summary, channel?.description]
            .compactMap { Self.normalizedDescription(from: $0) }
            .first
    }

    static func normalizedDescription(from text: String?, preservingLineBreaks: Bool = false) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        let renderedText = textWithoutMarkup(from: text, preservingLineBreaks: preservingLineBreaks)
        let collapsedText = preservingLineBreaks
            ? readableEpisodeNotes(from: renderedText)
            : renderedText
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

        return collapsedText.isEmpty ? nil : collapsedText
    }

    static func textWithoutMarkup(from text: String, preservingLineBreaks: Bool = false) -> String {
        var preparedText = text
        if preservingLineBreaks {
            preparedText = replaceRegex(#"(?i)<br\s*/?>"#, in: preparedText, with: "\n")
            preparedText = replaceRegex(#"(?i)</?(p|div|section|article|blockquote|h[1-6]|ul|ol)[^>]*>"#, in: preparedText, with: "\n\n")
            preparedText = replaceRegex(#"(?i)<li[^>]*>"#, in: preparedText, with: "\n- ")
            preparedText = replaceRegex(#"(?i)</li>"#, in: preparedText, with: "\n")
        }

        let withoutTags = preparedText.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeHTMLEntities(in: withoutTags)
    }

    static func readableEpisodeNotes(from text: String) -> String {
        var readable = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        readable = replaceRegex(#"[ \t\f\v]+"#, in: readable, with: " ")
        readable = replaceRegex(#" *\n *"#, in: readable, with: "\n")
        readable = stripMarkdownEmphasis(from: readable)
        readable = replaceRegex(#"(^|[^\n])(SPONSORS?)"#, in: readable, with: "$1\n\n$2\n")
        readable = replaceRegex(#"(^|[^\n])(---)"#, in: readable, with: "$1\n\n$2\n\n")
        readable = replaceRegex(#"(?i)(^|[^\n])(TIMESTAMPS:)"#, in: readable, with: "$1\n\n$2\n")
        readable = replaceRegex(#"([A-Za-z0-9\).])(https?://)"#, in: readable, with: "$1\n$2")
        readable = replaceRegex(#"(^|[^\n])(\d{2}:\d{2}:\d{2})"#, in: readable, with: "$1\n$2")
        readable = replaceRegex(#"\n{3,}"#, in: readable, with: "\n\n")

        return readable.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripMarkdownEmphasis(from text: String) -> String {
        var stripped = replaceRegex(#"\*\*([^*\n]+)\*\*"#, in: text, with: "$1")
        stripped = replaceRegex(#"__([^_\n]+)__"#, in: stripped, with: "$1")
        stripped = replaceRegex(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, in: stripped, with: "$1")
        stripped = replaceRegex(#"(?<!_)_([^_\n]+)_(?!_)"#, in: stripped, with: "$1")
        return stripped
    }

    static func replaceRegex(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }

    static func decodeHTMLEntities(in text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        let pattern = #"&#(x[0-9A-Fa-f]+|[0-9]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return decoded
        }

        let matches = regex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)).reversed()
        for match in matches {
            guard
                let fullRange = Range(match.range, in: decoded),
                let valueRange = Range(match.range(at: 1), in: decoded)
            else {
                continue
            }

            let value = String(decoded[valueRange])
            let codePoint: UInt32?
            if value.hasPrefix("x") {
                codePoint = UInt32(value.dropFirst(), radix: 16)
            } else {
                codePoint = UInt32(value, radix: 10)
            }

            if let codePoint, let scalar = UnicodeScalar(codePoint) {
                decoded.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }

        return decoded
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
            duration: item.iTunes?.duration,
            description: episodeDescription(from: item),
            enclosureURL: enclosureURL,
            sourceFeedURL: sourceFeedURL
        )
    }

    static func episodeDescription(from item: RSSFeedItem) -> String? {
        [item.content?.encoded, item.iTunes?.summary, item.description]
            .compactMap { Self.normalizedDescription(from: $0, preservingLineBreaks: true) }
            .first
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
