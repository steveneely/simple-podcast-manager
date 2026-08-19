import Foundation

public struct OPMLSubscription: Equatable, Sendable, Identifiable {
    public var title: String
    public var rssURL: URL

    public var id: String {
        rssURL.absoluteString
    }

    public init(title: String, rssURL: URL) {
        self.title = title
        self.rssURL = rssURL
    }
}

public struct OPMLSubscriptionImportPreview: Equatable, Sendable {
    public var subscriptionsToAdd: [OPMLSubscription]
    public var alreadySubscribedCount: Int
    public var duplicateEntryCount: Int
    public var invalidEntryCount: Int

    public init(
        subscriptionsToAdd: [OPMLSubscription],
        alreadySubscribedCount: Int,
        duplicateEntryCount: Int,
        invalidEntryCount: Int
    ) {
        self.subscriptionsToAdd = subscriptionsToAdd
        self.alreadySubscribedCount = alreadySubscribedCount
        self.duplicateEntryCount = duplicateEntryCount
        self.invalidEntryCount = invalidEntryCount
    }
}

public struct OPMLSubscriptionService {
    public init() {}

    public func importPreview(
        data: Data,
        existingSubscriptions: [FeedSubscription]
    ) throws -> OPMLSubscriptionImportPreview {
        let entries = try OPMLSubscriptionParser().parse(data: data)
        guard !entries.isEmpty else {
            throw OPMLSubscriptionError.noSubscriptions
        }

        var knownURLs = Set(existingSubscriptions.map { normalizedURL($0.rssURL) })
        var subscriptionsToAdd: [OPMLSubscription] = []
        var alreadySubscribedCount = 0
        var duplicateEntryCount = 0
        var invalidEntryCount = 0

        for entry in entries {
            guard let rssURL = validFeedURL(from: entry.xmlURLString) else {
                invalidEntryCount += 1
                continue
            }

            let normalizedRSSURL = normalizedURL(rssURL)
            if knownURLs.contains(normalizedRSSURL) {
                if existingSubscriptions.contains(where: { normalizedURL($0.rssURL) == normalizedRSSURL }) {
                    alreadySubscribedCount += 1
                } else {
                    duplicateEntryCount += 1
                }
                continue
            }

            knownURLs.insert(normalizedRSSURL)
            subscriptionsToAdd.append(
                OPMLSubscription(
                    title: title(for: entry, fallbackURL: rssURL),
                    rssURL: rssURL
                )
            )
        }

        return OPMLSubscriptionImportPreview(
            subscriptionsToAdd: subscriptionsToAdd,
            alreadySubscribedCount: alreadySubscribedCount,
            duplicateEntryCount: duplicateEntryCount,
            invalidEntryCount: invalidEntryCount
        )
    }

    public func exportSubscriptions(_ subscriptions: [FeedSubscription]) -> Data {
        let outlines = subscriptions
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { subscription -> String in
                let title = escapedXML(subscription.title)
                let url = escapedXML(subscription.rssURL.absoluteString)
                return "    <outline type=\"rss\" text=\"\(title)\" title=\"\(title)\" xmlUrl=\"\(url)\"/>"
            }
            .joined(separator: "\n")

        let document: String = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <opml version=\"2.0\">
          <head>
            <title>Simple Podcast Manager Subscriptions</title>
          </head>
          <body>
        \(outlines)
          </body>
        </opml>
        """
        return Data(document.utf8)
    }

    private func validFeedURL(from string: String) -> URL? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private func normalizedURL(_ url: URL) -> String {
        url.absoluteString.lowercased()
    }

    private func title(for entry: OPMLSubscriptionParser.Entry, fallbackURL: URL) -> String {
        let title = [entry.title, entry.text]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        return title ?? fallbackURL.host ?? fallbackURL.absoluteString
    }

    private func escapedXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

public enum OPMLSubscriptionError: LocalizedError, Equatable, Sendable {
    case invalidDocument
    case noSubscriptions

    public var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "That file is not a valid OPML subscription list."
        case .noSubscriptions:
            return "No podcast feed URLs were found in that OPML file."
        }
    }
}

private final class OPMLSubscriptionParser: NSObject, XMLParserDelegate {
    struct Entry {
        var title: String?
        var text: String?
        var xmlURLString: String
    }

    private(set) var entries: [Entry] = []
    private var isOPMLDocument = false

    func parse(data: Data) throws -> [Entry] {
        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse(), isOPMLDocument else {
            throw OPMLSubscriptionError.invalidDocument
        }
        return entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName.caseInsensitiveCompare("opml") == .orderedSame {
            isOPMLDocument = true
        }

        guard elementName.caseInsensitiveCompare("outline") == .orderedSame,
              let xmlURLString = attributeValue(named: "xmlUrl", in: attributeDict) else {
            return
        }

        entries.append(
            Entry(
                title: attributeValue(named: "title", in: attributeDict),
                text: attributeValue(named: "text", in: attributeDict),
                xmlURLString: xmlURLString
            )
        )
    }

    private func attributeValue(named name: String, in attributes: [String: String]) -> String? {
        attributes.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }
}
