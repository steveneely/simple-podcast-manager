import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct RSSFeedServiceTests {
    @Test
    func selectsLatestEpisodesPerEnabledFeed() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let feedURL = URL(string: "https://example.com/feed.xml")!
        FeedURLProtocolStub.stub(feedURL: feedURL, responseBody: """
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
          <channel>
            <title>Example Podcast</title>
            <description><![CDATA[<p>A podcast about <strong>simple</strong> things.</p>]]></description>
            <itunes:image href="https://example.com/artwork.jpg" />
            <item>
              <title>Episode 2</title>
              <guid>ep-2</guid>
              <pubDate>Tue, 22 Apr 2026 12:00:00 +0000</pubDate>
              <itunes:duration>1:02:03</itunes:duration>
              <description><![CDATA[Beth and David on model evaluations.**SPONSOR**Prolific - Quality data.https://example.com---TIMESTAMPS:00:00:00 Intro00:02:06 Sponsor break]]></description>
              <enclosure url="https://cdn.example.com/ep2.mp3" type="audio/mpeg"/>
            </item>
            <item>
              <title>Episode 1</title>
              <guid>ep-1</guid>
              <pubDate>Mon, 21 Apr 2026 12:00:00 +0000</pubDate>
              <enclosure url="https://cdn.example.com/ep1.mp3" type="audio/mpeg"/>
            </item>
          </channel>
        </rss>
        """)

        let service = RSSFeedService(session: URLSession(configuration: configuration), cacheStore: InMemoryFeedCacheStore())

        let result = try await service.fetchLatestEpisodes(for: [
            FeedSubscription(
                title: "Example Podcast",
                rssURL: feedURL,
                retentionPolicy: .keepLatestEpisodes(1),
                isEnabled: true
            )
        ])

        #expect(result.failures.isEmpty)
        #expect(result.selectedEpisodes.count == 2)
        #expect(result.selectedEpisodes.first?.title == "Episode 2")
        #expect(result.selectedEpisodes.first?.duration == 3_723)
        #expect(result.selectedEpisodes.first?.description?.contains("**SPONSOR**") == false)
        #expect(result.selectedEpisodes.first?.description?.contains("\n\nSPONSOR\nProlific") == true)
        #expect(result.selectedEpisodes.first?.description?.contains("\nhttps://example.com") == true)
        #expect(result.selectedEpisodes.first?.description?.contains("\nTIMESTAMPS:\n00:00:00 Intro\n00:02:06 Sponsor break") == true)
        #expect(result.selectedEpisodes.last?.title == "Episode 1")
        #expect(result.feedSummaries.first?.artworkURL == URL(string: "https://example.com/artwork.jpg"))
        #expect(result.feedSummaries.first?.description == "A podcast about simple things.")
    }

    @Test
    func formatsInlineSponsorSectionsInEpisodeDescriptions() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let feedURL = URL(string: "https://example.com/cognitive.xml")!
        FeedURLProtocolStub.stub(feedURL: feedURL, responseBody: """
        <rss version="2.0">
          <channel>
            <title>Cognitive Revolution</title>
            <item>
              <title>DeepMind at I/O</title>
              <guid>ep-1</guid>
              <pubDate>Tue, 22 Apr 2026 12:00:00 +0000</pubDate>
              <description><![CDATA[Logan Kilpatrick and Tulsee Doshi join for an in-person episode. Sponsors: Brave Search API: Brave Search API gives AI agents a fast, independent search index. Get $5 in free credits at https://brave.com/search/api/?mtm_campaign=q2-26-cognitive-revolution Sequence: Sequence handles the full revenue workflow for complex pricing. Book a demo at https://sequencehq.com Roboflow: Roboflow is an end-to-end visual AI platform. Read more at https://roboflow.com Claude: Claude by Anthropic is an AI collaborator. Get started at https://claude.ai/tcr]]></description>
              <enclosure url="https://cdn.example.com/ep1.mp3" type="audio/mpeg"/>
            </item>
          </channel>
        </rss>
        """)

        let service = RSSFeedService(session: URLSession(configuration: configuration), cacheStore: InMemoryFeedCacheStore())

        let result = try await service.fetchLatestEpisodes(for: [
            FeedSubscription(
                title: "Cognitive Revolution",
                rssURL: feedURL,
                isEnabled: true
            )
        ])

        let description = try #require(result.selectedEpisodes.first?.description)
        #expect(description.contains("\n\nSponsors:\nBrave Search API:") == true)
        #expect(description.contains("\n\nSequence: Sequence handles") == true)
        #expect(description.contains("\n\nRoboflow: Roboflow is") == true)
        #expect(description.contains("\n\nClaude: Claude by Anthropic") == true)
        #expect(description.contains("\nhttps://brave.com/search/api/") == true)
        #expect(description.contains("\nhttps://sequencehq.com") == true)
    }

    @Test
    func removesCommonReadabilityBoilerplateFromEpisodeDescriptions() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let feedURL = URL(string: "https://example.com/readable.xml")!
        FeedURLProtocolStub.stub(feedURL: feedURL, responseBody: """
        <rss version="2.0">
          <channel>
            <title>Readable Podcast</title>
            <item>
              <title>Readable Episode</title>
              <guid>ep-1</guid>
              <pubDate>Tue, 22 Apr 2026 12:00:00 +0000</pubDate>
              <description><![CDATA[Share this episode: https://example.com/share Sam&rsquo;s guest discusses &ldquo;The Hard Problem&rdquo; and what changed. Audio Transcript: Welcome to the transcript. This should not crowd the notes.]]></description>
              <enclosure url="https://cdn.example.com/ep1.mp3" type="audio/mpeg"/>
            </item>
          </channel>
        </rss>
        """)

        let service = RSSFeedService(session: URLSession(configuration: configuration), cacheStore: InMemoryFeedCacheStore())

        let result = try await service.fetchLatestEpisodes(for: [
            FeedSubscription(title: "Readable Podcast", rssURL: feedURL, isEnabled: true)
        ])

        let description = try #require(result.selectedEpisodes.first?.description)
        #expect(description == "Sam's guest discusses \"The Hard Problem\" and what changed.")
    }

    @Test
    func formatsEpisodeNoteSectionsAndRemovesPromotionalTails() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let feedURL = URL(string: "https://example.com/sections.xml")!
        FeedURLProtocolStub.stub(feedURL: feedURL, responseBody: """
        <rss version="2.0">
          <channel>
            <title>Sectioned Podcast</title>
            <item>
              <title>Sectioned Episode</title>
              <guid>ep-1</guid>
              <pubDate>Tue, 22 Apr 2026 12:00:00 +0000</pubDate>
              <description><![CDATA[The main conversation is about agent design. PSA for AI builders: Interested in alignment, governance, or AI safety? Learn more about the MATS Summer 2026 Fellowship and submit your name to be notified when applications open: https://matsprogram.org/s26-tcr. LINKS: Research paper: https://example.com/paper CHAPTERS: (00:00) Intro (09:25) Text-to-SQL PRODUCED BY: https://example.com/producer SOCIAL LINKS: https://example.com/social]]></description>
              <enclosure url="https://cdn.example.com/ep1.mp3" type="audio/mpeg"/>
            </item>
          </channel>
        </rss>
        """)

        let service = RSSFeedService(session: URLSession(configuration: configuration), cacheStore: InMemoryFeedCacheStore())

        let result = try await service.fetchLatestEpisodes(for: [
            FeedSubscription(title: "Sectioned Podcast", rssURL: feedURL, isEnabled: true)
        ])

        let description = try #require(result.selectedEpisodes.first?.description)
        #expect(description.contains("PSA for AI builders") == false)
        #expect(description.contains("PRODUCED BY") == false)
        #expect(description.contains("\n\nLINKS:\nResearch paper:") == true)
        #expect(description.contains("\n\nCHAPTERS:\n(00:00) Intro\n(09:25) Text-to-SQL") == true)
        #expect(description.contains("\nhttps://example.com/paper") == true)
    }

    @Test
    func recordsFailureForInvalidFeedData() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let feedURL = URL(string: "https://example.com/bad-feed.xml")!
        FeedURLProtocolStub.stub(feedURL: feedURL, responseBody: "<rss><channel><title>Broken")

        let service = RSSFeedService(session: URLSession(configuration: configuration), cacheStore: InMemoryFeedCacheStore())

        let result = try await service.fetchLatestEpisodes(for: [
            FeedSubscription(
                title: "Broken Feed",
                rssURL: feedURL,
                retentionPolicy: .keepLatestEpisodes(3),
                isEnabled: true
            )
        ])

        #expect(result.selectedEpisodes.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.subscriptionTitle == "Broken Feed")
    }

    @Test
    func ignoresDisabledFeeds() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let service = RSSFeedService(session: URLSession(configuration: configuration), cacheStore: InMemoryFeedCacheStore())

        let result = try await service.fetchLatestEpisodes(for: [
            FeedSubscription(
                title: "Disabled Feed",
                rssURL: URL(string: "https://example.com/disabled.xml")!,
                retentionPolicy: .keepLatestEpisodes(3),
                isEnabled: false
            )
        ])

        #expect(result.selectedEpisodes.isEmpty)
        #expect(result.failures.isEmpty)
    }

    @Test
    func parsesEpisodesFromTransistorEmbedWhenEnclosureIsBlank() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let feedURL = URL(string: "https://example.com/transistor.xml")!
        FeedURLProtocolStub.stub(feedURL: feedURL, responseBody: """
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <title>Example Podcast</title>
            <item>
              <title>Episode 1</title>
              <guid>ep-1</guid>
              <pubDate>Mon, 21 Apr 2026 12:00:00 +0000</pubDate>
              <content:encoded><![CDATA[
                <figure><iframe src="https://share.transistor.fm/e/14615be3/?color=444444&amp;background=ffffff"></iframe></figure>
              ]]></content:encoded>
              <enclosure url="" type="audio/mpeg"/>
            </item>
          </channel>
        </rss>
        """)

        let service = RSSFeedService(session: URLSession(configuration: configuration), cacheStore: InMemoryFeedCacheStore())

        let result = try await service.fetchLatestEpisodes(for: [
            FeedSubscription(
                title: "Example Podcast",
                rssURL: feedURL,
                retentionPolicy: .keepLatestEpisodes(3),
                isEnabled: true
            )
        ])

        #expect(result.failures.isEmpty)
        #expect(result.selectedEpisodes.count == 1)
        #expect(result.selectedEpisodes.first?.title == "Episode 1")
        #expect(result.selectedEpisodes.first?.enclosureURL == URL(string: "https://share.transistor.fm/e/14615be3/?color=444444&background=ffffff"))
    }

    @Test
    func sendsConditionalHeadersAndUsesCachedFeedWhenNotModified() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let subscriptionID = UUID()
        let feedURL = URL(string: "https://example.com/not-modified.xml")!
        let cachedFeed = CachedFeed(
            subscriptionID: subscriptionID,
            rssURL: feedURL,
            fetchedAt: Date(timeIntervalSince1970: 1_713_713_388),
            etag: "\"abc123\"",
            lastModified: "Wed, 24 Apr 2026 12:00:00 GMT",
            summary: FeedSummary(subscriptionID: subscriptionID, title: "Cached Podcast"),
            episodes: [
                Episode(
                    id: "cached-ep",
                    subscriptionID: subscriptionID,
                    podcastTitle: "Cached Podcast",
                    title: "Cached Episode",
                    publicationDate: Date(timeIntervalSince1970: 1_713_713_388),
                    enclosureURL: URL(string: "https://cdn.example.com/cached.mp3")!,
                    sourceFeedURL: feedURL
                )
            ]
        )
        let cacheStore = InMemoryFeedCacheStore(cachedFeeds: [subscriptionID: cachedFeed])
        FeedURLProtocolStub.stub(feedURL: feedURL, statusCode: 304, responseBody: "")

        let service = RSSFeedService(session: URLSession(configuration: configuration), cacheStore: cacheStore)
        let result = try await service.fetchLatestEpisodes(for: [
            FeedSubscription(id: subscriptionID, title: "Cached Podcast", rssURL: feedURL)
        ])

        #expect(result.failures.isEmpty)
        #expect(result.selectedEpisodes.map(\.title) == ["Cached Episode"])
        #expect(FeedURLProtocolStub.lastHeader("If-None-Match", for: feedURL) == "\"abc123\"")
        #expect(FeedURLProtocolStub.lastHeader("If-Modified-Since", for: feedURL) == "Wed, 24 Apr 2026 12:00:00 GMT")
    }

    @Test
    func savesUpdatedFeedAndValidatorsAfterSuccessfulRefresh() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let subscriptionID = UUID()
        let feedURL = URL(string: "https://example.com/updated.xml")!
        FeedURLProtocolStub.stub(
            feedURL: feedURL,
            statusCode: 200,
            headers: [
                "ETag": "\"new-etag\"",
                "Last-Modified": "Fri, 24 Apr 2026 12:00:00 GMT",
            ],
            responseBody: """
            <rss version="2.0">
              <channel>
                <title>Updated Podcast</title>
                <item>
                  <title>Updated Episode</title>
                  <guid>updated-ep</guid>
                  <pubDate>Fri, 24 Apr 2026 12:00:00 +0000</pubDate>
                  <enclosure url="https://cdn.example.com/updated.mp3" type="audio/mpeg"/>
                </item>
              </channel>
            </rss>
            """
        )
        let cacheStore = InMemoryFeedCacheStore()

        let service = RSSFeedService(
            session: URLSession(configuration: configuration),
            cacheStore: cacheStore,
            currentDate: { Date(timeIntervalSince1970: 1_777_000_000) }
        )
        let result = try await service.fetchLatestEpisodes(for: [
            FeedSubscription(id: subscriptionID, title: "Updated Podcast", rssURL: feedURL)
        ])

        #expect(result.failures.isEmpty)
        #expect(result.selectedEpisodes.map(\.title) == ["Updated Episode"])
        #expect(cacheStore.cachedFeeds[subscriptionID]?.etag == "\"new-etag\"")
        #expect(cacheStore.cachedFeeds[subscriptionID]?.lastModified == "Fri, 24 Apr 2026 12:00:00 GMT")
        #expect(cacheStore.cachedFeeds[subscriptionID]?.episodes.map(\.title) == ["Updated Episode"])
    }

    @Test
    func reportsClearWarningWhenUsingCachedFeedAfterRefreshFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let subscriptionID = UUID()
        let feedURL = URL(string: "https://example.com/gone.xml")!
        let cachedFeed = CachedFeed(
            subscriptionID: subscriptionID,
            rssURL: feedURL,
            fetchedAt: Date(timeIntervalSince1970: 1_713_713_388),
            summary: FeedSummary(subscriptionID: subscriptionID, title: "Cached Podcast"),
            episodes: [
                Episode(
                    id: "cached-ep",
                    subscriptionID: subscriptionID,
                    podcastTitle: "Cached Podcast",
                    title: "Cached Episode",
                    publicationDate: Date(timeIntervalSince1970: 1_713_713_388),
                    enclosureURL: URL(string: "https://cdn.example.com/cached.mp3")!,
                    sourceFeedURL: feedURL
                )
            ]
        )
        let cacheStore = InMemoryFeedCacheStore(cachedFeeds: [subscriptionID: cachedFeed])
        FeedURLProtocolStub.stub(feedURL: feedURL, statusCode: 410, responseBody: "")

        let service = RSSFeedService(session: URLSession(configuration: configuration), cacheStore: cacheStore)
        let result = try await service.fetchLatestEpisodes(for: [
            FeedSubscription(id: subscriptionID, title: "Cached Podcast", rssURL: feedURL)
        ])

        #expect(result.selectedEpisodes.map(\.title) == ["Cached Episode"])
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.message.contains("Could not refresh this feed. Showing saved episodes from") == true)
        #expect(result.failures.first?.message.contains("410") == true)
    }
}

private final class FeedURLProtocolStub: URLProtocol, @unchecked Sendable {
    private static let store = FeedURLStubStore()

    static func stub(feedURL: URL, responseBody: String) {
        stub(feedURL: feedURL, statusCode: 200, headers: [:], responseBody: responseBody)
    }

    static func stub(feedURL: URL, statusCode: Int, headers: [String: String] = [:], responseBody: String) {
        store.set(FeedURLStub(statusCode: statusCode, headers: headers, body: responseBody), for: feedURL.absoluteString)
    }

    static func lastHeader(_ field: String, for feedURL: URL) -> String? {
        store.lastHeaders(for: feedURL.absoluteString)?[field]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let url = request.url,
            let stub = Self.store.stub(for: url.absoluteString),
            let data = stub.body.data(using: .utf8)
        else {
            client?.urlProtocol(
                self,
                didFailWithError: FeedServiceError.invalidResponse
            )
            return
        }
        Self.store.setHeaders(
            [
                "If-None-Match": request.value(forHTTPHeaderField: "If-None-Match") ?? "",
                "If-Modified-Since": request.value(forHTTPHeaderField: "If-Modified-Since") ?? "",
            ],
            for: url.absoluteString
        )

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct FeedURLStub {
    var statusCode: Int
    var headers: [String: String]
    var body: String
}

private final class FeedURLStubStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stubs: [String: FeedURLStub] = [:]
    private var headersByURLString: [String: [String: String]] = [:]

    func set(_ stub: FeedURLStub, for urlString: String) {
        lock.lock()
        defer { lock.unlock() }
        stubs[urlString] = stub
    }

    func stub(for urlString: String) -> FeedURLStub? {
        lock.lock()
        defer { lock.unlock() }
        return stubs[urlString]
    }

    func setHeaders(_ headers: [String: String], for urlString: String) {
        lock.lock()
        defer { lock.unlock() }
        headersByURLString[urlString] = headers
    }

    func lastHeaders(for urlString: String) -> [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return headersByURLString[urlString]
    }
}

private final class InMemoryFeedCacheStore: FeedCacheStore, @unchecked Sendable {
    var cachedFeeds: [UUID: CachedFeed]

    init(cachedFeeds: [UUID: CachedFeed] = [:]) {
        self.cachedFeeds = cachedFeeds
    }

    func loadCachedFeed(for subscription: FeedSubscription) throws -> CachedFeed? {
        guard let cachedFeed = cachedFeeds[subscription.id], cachedFeed.rssURL == subscription.rssURL else {
            return nil
        }
        return cachedFeed
    }

    func saveCachedFeed(_ cachedFeed: CachedFeed) throws {
        cachedFeeds[cachedFeed.subscriptionID] = cachedFeed
    }

    func deleteCachedFeed(for subscriptionID: UUID) throws {
        cachedFeeds[subscriptionID] = nil
    }
}
