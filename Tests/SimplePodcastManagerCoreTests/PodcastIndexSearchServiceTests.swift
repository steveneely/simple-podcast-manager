import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct PodcastIndexSearchServiceTests {
    @Test
    func searchesKeylessEndpointAndMapsUsableResults() async throws {
        let responseData = Data(
            """
            {
              "resultCount": 4,
              "results": [
                {
                  "artistName": " Tony Sindelar ",
                  "collectionName": " Batman University ",
                  "trackName": "Batman University",
                  "feedUrl": "https://feeds.example.com/batman",
                  "artworkUrl600": "https://images.example.com/batman.jpg",
                  "trackCount": 19,
                  "collectionExplicitness": "cleaned"
                },
                {
                  "collectionName": "Duplicate",
                  "feedUrl": "http://feeds.example.com:80/batman/"
                },
                {
                  "trackName": "HTTP Artwork",
                  "feedUrl": "http://feeds.example.com/http-show",
                  "artworkUrl100": "http://images.example.com/insecure.jpg",
                  "collectionExplicitness": "explicit"
                },
                {
                  "collectionName": "Unsupported Feed",
                  "feedUrl": "ftp://feeds.example.com/show"
                }
              ]
            }
            """.utf8
        )
        let session = PodcastSearchSessionStub(data: responseData)
        let service = PodcastIndexSearchService(session: session)

        let results = try await service.searchPodcasts(matching: "  batman university  ")

        #expect(results == [
            PodcastSearchResult(
                title: "Batman University",
                author: "Tony Sindelar",
                feedURL: URL(string: "https://feeds.example.com/batman")!,
                artworkURL: URL(string: "https://images.example.com/batman.jpg")!,
                episodeCount: 19
            ),
            PodcastSearchResult(
                title: "HTTP Artwork",
                feedURL: URL(string: "http://feeds.example.com/http-show")!,
                artworkURL: nil,
                episodeCount: nil,
                isExplicit: true
            ),
        ])

        let request = try #require(await session.lastRequest)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "api.podcastindex.org")
        #expect(components.path == "/search")
        #expect(components.queryItems == [URLQueryItem(name: "term", value: "batman university")])
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "SimplePodcastManager/PodcastSearch")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test
    func rejectsUnsuccessfulHTTPResponse() async {
        let session = PodcastSearchSessionStub(data: Data(), statusCode: 503)
        let service = PodcastIndexSearchService(session: session)

        await #expect(throws: PodcastSearchError.requestFailed(statusCode: 503)) {
            try await service.searchPodcasts(matching: "example")
        }
    }

    @Test
    func rejectsMalformedSearchData() async {
        let session = PodcastSearchSessionStub(data: Data("not json".utf8))
        let service = PodcastIndexSearchService(session: session)

        await #expect(throws: PodcastSearchError.invalidData) {
            try await service.searchPodcasts(matching: "example")
        }
    }

    @Test
    func emptyQueryReturnsWithoutMakingARequest() async throws {
        let session = PodcastSearchSessionStub(data: Data())
        let service = PodcastIndexSearchService(session: session)

        let results = try await service.searchPodcasts(matching: "   ")

        #expect(results.isEmpty)
        #expect(await session.lastRequest == nil)
    }
}

private actor PodcastSearchSessionStub: HTTPDataLoading {
    private let data: Data
    private let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}
