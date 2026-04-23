import Foundation
import Testing
@testable import PodcastSwiftCore

struct PodcastIndexDiscoveryServiceTests {
    @Test
    func authorizationHeaderMatchesExpectedSha1Value() {
        let credentials = PodcastDirectoryCredentials(
            apiKey: "UXKCGDSYGUUEVQJSYDZH",
            apiSecret: "yzJe2eE7XV-3eY576dyRZ6wXyAbndh6LUrCZ8KN|"
        )

        let header = PodcastIndexDiscoveryService.authorizationHeader(
            credentials: credentials,
            unixTimestamp: "1613713388"
        )

        #expect(header == "73a1fffed61c1d30d858beb1fc48f355386449d2")
    }

    @Test
    func decodesSearchResponseIntoDiscoveryResults() async throws {
        let responseData = """
        {
          "feeds": [
            {
              "id": 42,
              "title": "Accidental Tech Podcast",
              "url": "https://atp.fm/rss",
              "author": "ATP",
              "description": "Three nerds talking tech.",
              "artwork": "https://example.com/atp.jpg"
            }
          ]
        }
        """.data(using: .utf8)!

        let session = URLSession(configuration: .ephemeral)
        let service = PodcastIndexDiscoveryService(
            credentials: PodcastDirectoryCredentials(apiKey: "key", apiSecret: "secret"),
            session: session,
            baseURL: URL(string: "https://api.podcastindex.org/api/1.0")!,
            userAgent: "PodcastSwiftTests/1.0",
            dateProvider: { Date(timeIntervalSince1970: 1_613_713_388) }
        )

        URLProtocolStub.stub(
            data: responseData,
            response: try #require(HTTPURLResponse(
                url: URL(string: "https://api.podcastindex.org/api/1.0/search/byterm?q=atp")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let stubbedService = PodcastIndexDiscoveryService(
            credentials: PodcastDirectoryCredentials(apiKey: "key", apiSecret: "secret"),
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://api.podcastindex.org/api/1.0")!,
            userAgent: "PodcastSwiftTests/1.0",
            dateProvider: { Date(timeIntervalSince1970: 1_613_713_388) }
        )

        let results = try await stubbedService.searchPodcasts(matching: "atp")

        #expect(results.count == 1)
        #expect(results.first?.title == "Accidental Tech Podcast")
        #expect(results.first?.feedURL == URL(string: "https://atp.fm/rss"))
        #expect(results.first?.isSubscribable == true)
        _ = service
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var stubbedData: Data?
    nonisolated(unsafe) private static var stubbedResponse: URLResponse?

    static func stub(data: Data, response: URLResponse) {
        stubbedData = data
        stubbedResponse = response
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let response = Self.stubbedResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data = Self.stubbedData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
