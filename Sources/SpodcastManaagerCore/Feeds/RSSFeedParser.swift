import Foundation

public final class RSSFeedParser: NSObject {
    public override init() {}

    public func parse(data: Data, sourceFeedURL: URL, subscriptionID: UUID?) throws -> ParsedRSSFeed {
        let delegate = RSSFeedParserDelegate(sourceFeedURL: sourceFeedURL, subscriptionID: subscriptionID)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw FeedServiceError.invalidFeedData
        }

        return delegate.makeParsedFeed()
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

private final class RSSFeedParserDelegate: NSObject, XMLParserDelegate {
    private let sourceFeedURL: URL
    private let subscriptionID: UUID?

    private var feedTitle: String?
    private var feedArtworkURLString: String?
    private var parsedEpisodes: [Episode] = []

    private var currentElement = ""
    private var currentText = ""
    private var channelDepth = 0
    private var imageDepth = 0
    private var itemDepth = 0
    private var itemBuilder = RSSItemBuilder()

    init(sourceFeedURL: URL, subscriptionID: UUID?) {
        self.sourceFeedURL = sourceFeedURL
        self.subscriptionID = subscriptionID
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        let normalizedElement = RSSFeedParserDelegate.normalizedElementName(
            elementName: elementName,
            qualifiedName: qName
        )
        currentElement = normalizedElement
        currentText = ""

        if currentElement == "channel" {
            channelDepth += 1
        } else if channelDepth > 0 && itemDepth == 0 && currentElement == "image" {
            imageDepth += 1
        } else if currentElement == "item" {
            itemDepth += 1
            itemBuilder = RSSItemBuilder()
        }

        if itemDepth > 0 && currentElement == "enclosure" {
            itemBuilder.enclosureURL = attributeDict["url"]
        } else if channelDepth > 0 && itemDepth == 0 && currentElement == "itunes:image" {
            feedArtworkURLString = attributeDict["href"] ?? feedArtworkURLString
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let normalizedElement = RSSFeedParserDelegate.normalizedElementName(
            elementName: elementName,
            qualifiedName: qName
        )
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if itemDepth > 0 {
            switch normalizedElement {
            case "title":
                if !text.isEmpty { itemBuilder.title = text }
            case "guid":
                if !text.isEmpty { itemBuilder.guid = text }
            case "pubdate":
                if !text.isEmpty { itemBuilder.publicationDate = RSSDateParser.parse(text) }
            case "description":
                if !text.isEmpty { itemBuilder.descriptionHTML = text }
            case "itunes:summary":
                if !text.isEmpty { itemBuilder.summaryHTML = text }
            case "content:encoded":
                if !text.isEmpty { itemBuilder.contentHTML = text }
            case "enclosure":
                break
            default:
                break
            }

            if normalizedElement == "item" {
                if let episode = itemBuilder.makeEpisode(
                    feedTitle: feedTitle ?? "Unknown Podcast",
                    sourceFeedURL: sourceFeedURL,
                    subscriptionID: subscriptionID
                ) {
                    parsedEpisodes.append(episode)
                }
                itemDepth -= 1
            }
        } else if channelDepth > 0 {
            if normalizedElement == "title", feedTitle == nil, !text.isEmpty {
                feedTitle = text
            }
            if normalizedElement == "url", imageDepth > 0, !text.isEmpty, feedArtworkURLString == nil {
                feedArtworkURLString = text
            }
            if normalizedElement == "image", imageDepth > 0 {
                imageDepth -= 1
            }

            if normalizedElement == "channel" {
                channelDepth -= 1
            }
        }

        currentElement = ""
        currentText = ""
    }

    func makeParsedFeed() -> ParsedRSSFeed {
        ParsedRSSFeed(
            title: feedTitle ?? sourceFeedURL.absoluteString,
            artworkURL: feedArtworkURLString.flatMap(URL.init(string:)),
            episodes: parsedEpisodes
        )
    }

    private static func normalizedElementName(elementName: String, qualifiedName: String?) -> String {
        (qualifiedName ?? elementName).lowercased()
    }
}

private struct RSSItemBuilder {
    var title: String?
    var guid: String?
    var publicationDate: Date?
    var enclosureURL: String?
    var descriptionHTML: String?
    var summaryHTML: String?
    var contentHTML: String?

    func makeEpisode(feedTitle: String, sourceFeedURL: URL, subscriptionID: UUID?) -> Episode? {
        let resolvedURLString = normalizedEnclosureURL ?? fallbackEmbedURLString

        guard
            let title, !title.isEmpty,
            let resolvedURLString,
            let parsedEnclosureURL = URL(string: resolvedURLString)
        else {
            return nil
        }

        let episodeID = guid ?? parsedEnclosureURL.absoluteString

        return Episode(
            id: episodeID,
            subscriptionID: subscriptionID,
            podcastTitle: feedTitle,
            title: title,
            publicationDate: publicationDate,
            enclosureURL: parsedEnclosureURL,
            sourceFeedURL: sourceFeedURL
        )
    }

    private var normalizedEnclosureURL: String? {
        guard let enclosureURL = enclosureURL?.trimmingCharacters(in: .whitespacesAndNewlines), !enclosureURL.isEmpty else {
            return nil
        }

        return enclosureURL
    }

    private var fallbackEmbedURLString: String? {
        [contentHTML, summaryHTML, descriptionHTML]
            .compactMap(Self.extractTransistorEmbedURL(from:))
            .first
    }

    private static func extractTransistorEmbedURL(from text: String?) -> String? {
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

private enum RSSDateParser {
    private static let formatters: [DateFormatter] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        ]

        return formats.map { format in
            let formatterCopy = DateFormatter()
            formatterCopy.locale = formatter.locale
            formatterCopy.timeZone = formatter.timeZone
            formatterCopy.dateFormat = format
            return formatterCopy
        }
    }()

    static func parse(_ text: String) -> Date? {
        formatters.lazy.compactMap { $0.date(from: text) }.first
    }
}
