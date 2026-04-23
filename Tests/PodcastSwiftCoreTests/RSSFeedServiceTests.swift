import Foundation
import Testing
@testable import PodcastSwiftCore

struct RSSFeedServiceTests {
    @Test
    func selectsLatestEpisodesPerEnabledFeed() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let feedURL = URL(string: "https://example.com/feed.xml")!
        FeedURLProtocolStub.stub(feedURL: feedURL, responseBody: """
        <rss version="2.0">
          <channel>
            <title>Example Podcast</title>
            <item>
              <title>Episode 2</title>
              <guid>ep-2</guid>
              <pubDate>Tue, 22 Apr 2026 12:00:00 +0000</pubDate>
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

        let service = RSSFeedService(session: URLSession(configuration: configuration))

        let result = try await service.fetchLatestEpisodes(for: [
            FeedSubscription(
                title: "Example Podcast",
                rssURL: feedURL,
                retentionPolicy: .keepLatestEpisodes(1),
                isEnabled: true
            )
        ])

        #expect(result.failures.isEmpty)
        #expect(result.selectedEpisodes.count == 1)
        #expect(result.selectedEpisodes.first?.title == "Episode 2")
    }

    @Test
    func recordsFailureForInvalidFeedData() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]

        let feedURL = URL(string: "https://example.com/bad-feed.xml")!
        FeedURLProtocolStub.stub(feedURL: feedURL, responseBody: "<rss><channel><title>Broken")

        let service = RSSFeedService(session: URLSession(configuration: configuration))

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

        let service = RSSFeedService(session: URLSession(configuration: configuration))

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
}

private final class FeedURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var stubs: [String: String] = [:]

    static func stub(feedURL: URL, responseBody: String) {
        stubs[feedURL.absoluteString] = responseBody
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
            let body = Self.stubs[url.absoluteString],
            let data = body.data(using: .utf8)
        else {
            client?.urlProtocol(
                self,
                didFailWithError: FeedServiceError.invalidResponse
            )
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
