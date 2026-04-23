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
    public var episodes: [Episode]

    public init(title: String, episodes: [Episode]) {
        self.title = title
        self.episodes = episodes
    }
}

private final class RSSFeedParserDelegate: NSObject, XMLParserDelegate {
    private let sourceFeedURL: URL
    private let subscriptionID: UUID?

    private var feedTitle: String?
    private var parsedEpisodes: [Episode] = []

    private var currentElement = ""
    private var currentText = ""
    private var channelDepth = 0
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
        currentElement = elementName.lowercased()
        currentText = ""

        if currentElement == "channel" {
            channelDepth += 1
        } else if currentElement == "item" {
            itemDepth += 1
            itemBuilder = RSSItemBuilder()
        }

        if itemDepth > 0 && currentElement == "enclosure" {
            itemBuilder.enclosureURL = attributeDict["url"]
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
        let normalizedElement = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if itemDepth > 0 {
            switch normalizedElement {
            case "title":
                if !text.isEmpty { itemBuilder.title = text }
            case "guid":
                if !text.isEmpty { itemBuilder.guid = text }
            case "pubdate":
                if !text.isEmpty { itemBuilder.publicationDate = RSSDateParser.parse(text) }
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
            episodes: parsedEpisodes
        )
    }
}

private struct RSSItemBuilder {
    var title: String?
    var guid: String?
    var publicationDate: Date?
    var enclosureURL: String?

    func makeEpisode(feedTitle: String, sourceFeedURL: URL, subscriptionID: UUID?) -> Episode? {
        guard
            let title, !title.isEmpty,
            let enclosureURL,
            let parsedEnclosureURL = URL(string: enclosureURL)
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
