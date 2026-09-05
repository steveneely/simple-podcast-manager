import Foundation
import FeedKit

public final class RSSFeedParser: Sendable {
    public init() {}

    public func parse(data: Data, sourceFeedURL: URL, subscriptionID: UUID?) throws -> ParsedRSSFeed {
        let rssFeed: RSSFeed
        do {
            rssFeed = try RSSFeed(data: data)
        } catch {
            throw FeedServiceError.invalidFeedData
        }

        return Self.makeParsedRSSFeed(from: rssFeed, sourceFeedURL: sourceFeedURL, subscriptionID: subscriptionID)
    }
}

public struct ParsedRSSFeed: Equatable, Sendable {
    public var title: String
    public var artworkURL: URL?
    public var description: String?
    public var itemCount: Int
    public var episodes: [Episode]

    public init(title: String, artworkURL: URL? = nil, description: String? = nil, itemCount: Int = 0, episodes: [Episode]) {
        self.title = title
        self.artworkURL = artworkURL
        self.description = description
        self.itemCount = itemCount
        self.episodes = episodes
    }
}

private extension RSSFeedParser {
    static let regularExpressionCache = RegularExpressionCache()

    static func makeParsedRSSFeed(from feed: RSSFeed, sourceFeedURL: URL, subscriptionID: UUID?) -> ParsedRSSFeed {
        let feedTitle = feed.channel?.title ?? sourceFeedURL.absoluteString
        let artworkURL = channelArtworkURL(from: feed.channel)
        let description = channelDescription(from: feed.channel)
        let items = feed.channel?.items ?? []
        let episodes = items.compactMap {
            makeEpisode(
                from: $0,
                feedTitle: feedTitle,
                feedArtworkURL: artworkURL,
                sourceFeedURL: sourceFeedURL,
                subscriptionID: subscriptionID
            )
        }

        return ParsedRSSFeed(
            title: feedTitle,
            artworkURL: artworkURL,
            description: description,
            itemCount: items.count,
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
        firstNormalizedDescription(from: [channel?.iTunes?.summary, channel?.description])
    }

    static func firstNormalizedDescription(
        from candidates: [String?],
        preservingLineBreaks: Bool = false
    ) -> String? {
        for candidate in candidates {
            if let description = normalizedDescription(
                from: candidate,
                preservingLineBreaks: preservingLineBreaks
            ) {
                return description
            }
        }

        return nil
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
        if preservingLineBreaks, preparedText.contains("<") {
            preparedText = replaceRegex(#"(?i)<br\s*/?>"#, in: preparedText, with: "\n")
            preparedText = replaceRegex(#"(?i)</?(p|div|section|article|blockquote|h[1-6]|ul|ol)[^>]*>"#, in: preparedText, with: "\n\n")
            preparedText = replaceRegex(#"(?i)<li[^>]*>"#, in: preparedText, with: "\n- ")
            preparedText = replaceRegex(#"(?i)</li>"#, in: preparedText, with: "\n")
        }

        let withoutTags = preparedText.contains("<")
            ? replaceRegex(#"<[^>]+>"#, in: preparedText, with: " ")
            : preparedText
        return decodeHTMLEntities(in: withoutTags)
    }

    static func readableEpisodeNotes(from text: String) -> String {
        var readable = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        readable = replaceRegex(#"[ \t\f\v]+"#, in: readable, with: " ")
        readable = replaceRegex(#" *\n *"#, in: readable, with: "\n")
        if readable.contains("*") || readable.contains("_") {
            readable = stripMarkdownEmphasis(from: readable)
        }
        readable = stripReadabilityBoilerplate(from: readable)
        if readable.range(of: "sponsor", options: .caseInsensitive) != nil {
            readable = replaceRegex(#"(?i)(^|[^\n])(Sponsors:) *"#, in: readable, with: "$1\n\n$2\n")
            readable = replaceRegex(#"(^|[^\n])(SPONSORS?) *"#, in: readable, with: "$1\n\n$2\n")
            readable = splitSponsorLabels(in: readable)
        }
        if readable.contains("---") {
            readable = replaceRegex(#"(^|[^\n])(---)"#, in: readable, with: "$1\n\n$2\n\n")
        }
        if containsEpisodeSectionHeading(in: readable) {
            readable = replaceRegex(
                #"(?i)(^|[^\n])((?:LINKS|EPISODE LINKS|PODCAST INFO|SUPPORT & CONNECT|OUTLINE|CHAPTERS|RECOMMENDED PODCAST):)"#,
                in: readable,
                with: "$1\n\n$2\n"
            )
        }
        if readable.range(of: "TIMESTAMPS:", options: .caseInsensitive) != nil {
            readable = replaceRegex(#"(?i)(^|[^\n])(TIMESTAMPS:)"#, in: readable, with: "$1\n\n$2\n")
        }
        if readable.range(of: "http", options: .caseInsensitive) != nil {
            readable = replaceRegex(#"(?<!\n) +(https?://)"#, in: readable, with: "\n$1")
            readable = replaceRegex(#"([A-Za-z0-9\).])(https?://)"#, in: readable, with: "$1\n$2")
        }
        readable = replaceRegex(
            #"(^|[^\n])((?:\(\d{1,2}:\d{2}(?::\d{2})?\)|\d{1,2}:\d{2}(?::\d{2})? ?[–-]|\d{2}:\d{2}:\d{2}))"#,
            in: readable,
            with: "$1\n$2"
        )
        readable = replaceRegex(#" *\n *"#, in: readable, with: "\n")
        readable = replaceRegex(#"\n{3,}"#, in: readable, with: "\n\n")
        readable = replaceRegex(#"(?i)((?:CHAPTERS|OUTLINE|TIMESTAMPS):)\n\n(\(?\d)"#, in: readable, with: "$1\n$2")

        return readable.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripReadabilityBoilerplate(from text: String) -> String {
        var cleaned = trimTranscriptSections(in: text)
        if cleaned.range(of: "Share this episode:", options: .caseInsensitive) != nil {
            cleaned = replaceRegex(#"(?i)(^|\n)?Share this episode:\s*https?://\S+\s*"#, in: cleaned, with: "$1")
        }
        if cleaned.range(of: "PSA for AI builders:", options: .caseInsensitive) != nil {
            cleaned = replaceRegex(
                #"(?i)\bPSA for AI builders:\s*Interested in alignment, governance, or AI safety\?\s*Learn more about the MATS [^.]+:\s*https?://\S+\.?\s*"#,
                in: cleaned,
                with: ""
            )
        }
        cleaned = trimTrailingSections(in: cleaned, markers: ["PRODUCED BY:", "SOCIAL LINKS:"])
        return cleaned
    }

    static func containsEpisodeSectionHeading(in text: String) -> Bool {
        ["LINKS:", "EPISODE LINKS:", "PODCAST INFO:", "SUPPORT & CONNECT:", "OUTLINE:", "CHAPTERS:", "RECOMMENDED PODCAST:"]
            .contains { text.range(of: $0, options: .caseInsensitive) != nil }
    }

    static func trimTranscriptSections(in text: String) -> String {
        let markers = ["Audio Transcript:", "AUDIO TRANSCRIPT"]
        guard let markerRange = markers
            .compactMap({ text.range(of: $0, options: [.caseInsensitive]) })
            .min(by: { $0.lowerBound < $1.lowerBound })
        else {
            return text
        }

        return String(text[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trimTrailingSections(in text: String, markers: [String]) -> String {
        guard let markerRange = markers
            .compactMap({ text.range(of: $0, options: [.caseInsensitive]) })
            .min(by: { $0.lowerBound < $1.lowerBound })
        else {
            return text
        }

        return String(text[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func splitSponsorLabels(in text: String) -> String {
        let sponsorHeadings = ["Sponsors:\n", "SPONSOR\n", "SPONSORS\n"]
        guard let headingRange = sponsorHeadings.compactMap({ text.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return text
        }

        let prefix = text[..<headingRange.upperBound]
        let sponsorText = text[headingRange.upperBound...]
        var splitSponsorText = replaceRegex(
            #"(https?://\S+)\s+([A-Z][A-Za-z0-9.-]*(?: [A-Z][A-Za-z0-9.-]*){0,3}:) (?=[A-Z])"#,
            in: String(sponsorText),
            with: "$1\n\n$2 "
        )
        splitSponsorText = replaceRegex(
            #"([.!?])\s+([A-Z][A-Za-z0-9.-]*(?: [A-Z][A-Za-z0-9.-]*){0,3}:) (?=[A-Z])"#,
            in: splitSponsorText,
            with: "$1\n\n$2 "
        )

        return String(prefix) + splitSponsorText
    }

    static func stripMarkdownEmphasis(from text: String) -> String {
        var stripped = replaceRegex(#"\*\*([^*\n]+)\*\*"#, in: text, with: "$1")
        stripped = replaceRegex(#"__([^_\n]+)__"#, in: stripped, with: "$1")
        stripped = replaceRegex(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, in: stripped, with: "$1")
        stripped = replaceRegex(#"(?<!_)_([^_\n]+)_(?!_)"#, in: stripped, with: "$1")
        return stripped
    }

    static func replaceRegex(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = regularExpressionCache.expression(for: pattern) else {
            return text
        }

        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }

    static func decodeHTMLEntities(in text: String) -> String {
        guard text.contains("&") else {
            return text
        }

        let namedEntities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\"",
            "&ldquo;": "\"",
            "&ndash;": "-",
            "&mdash;": "-",
            "&hellip;": "...",
            "&eacute;": "e",
            "&Eacute;": "E",
            "&ouml;": "o",
            "&Ouml;": "O",
        ]
        var decoded = text
        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

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
        feedArtworkURL: URL?,
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
            publicationDate: PublicationDateNormalizer.normalize(item.pubDate),
            duration: item.iTunes?.duration,
            description: episodeDescription(from: item),
            artworkURL: episodeArtworkURL(from: item) ?? feedArtworkURL,
            enclosureURL: enclosureURL,
            sourceFeedURL: sourceFeedURL
        )
    }

    static func episodeArtworkURL(from item: RSSFeedItem) -> URL? {
        guard let href = item.iTunes?.image?.attributes?.href else {
            return nil
        }

        return URL(string: href)
    }

    static func episodeDescription(from item: RSSFeedItem) -> String? {
        firstNormalizedDescription(
            from: [item.content?.encoded, item.iTunes?.summary, item.description],
            preservingLineBreaks: true
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
            let regex = regularExpressionCache.expression(for: pattern),
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

/// `NSCache` synchronizes its own access, and cached regular expressions are immutable after creation.
private final class RegularExpressionCache: @unchecked Sendable {
    private let expressions = NSCache<NSString, NSRegularExpression>()

    func expression(for pattern: String) -> NSRegularExpression? {
        let cacheKey = pattern as NSString
        if let cachedExpression = expressions.object(forKey: cacheKey) {
            return cachedExpression
        }

        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        expressions.setObject(expression, forKey: cacheKey)
        return expression
    }
}
