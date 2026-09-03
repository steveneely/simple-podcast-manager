import Foundation

public struct PodcastIndexSearchService: PodcastSearching {
    private static let searchEndpoint = URL(string: "https://api.podcastindex.org/search")!

    private let session: any HTTPDataLoading

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    public init(session: any HTTPDataLoading) {
        self.session = session
    }

    public func searchPodcasts(matching query: String) async throws -> [PodcastSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        var components = URLComponents(
            url: Self.searchEndpoint,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "term", value: normalizedQuery)]
        guard let searchURL = components.url else {
            throw PodcastSearchError.invalidRequest
        }

        var request = URLRequest(
            url: searchURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SimplePodcastManager/PodcastSearch", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PodcastSearchError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PodcastSearchError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let responseBody: SearchResponse
        do {
            responseBody = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw PodcastSearchError.invalidData
        }

        var seenFeedURLs: Set<String> = []
        return responseBody.results.compactMap { result in
            guard
                let feedURL = Self.webURL(from: result.feedURL),
                seenFeedURLs.insert(FeedURLIdentity.normalized(feedURL)).inserted
            else {
                return nil
            }

            let title = Self.normalizedText(result.collectionName)
                ?? Self.normalizedText(result.trackName)
                ?? feedURL.host(percentEncoded: false)
                ?? feedURL.absoluteString
            let artworkURL = Self.webURL(from: result.artworkURL600 ?? result.artworkURL100)
                .flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }

            return PodcastSearchResult(
                title: title,
                author: Self.normalizedText(result.artistName),
                feedURL: feedURL,
                artworkURL: artworkURL,
                episodeCount: result.trackCount,
                isExplicit: result.collectionExplicitness?.lowercased() == "explicit"
            )
        }
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    private static func webURL(from value: String?) -> URL? {
        guard
            let value = normalizedText(value),
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }
}

public enum PodcastSearchError: LocalizedError, Equatable, Sendable {
    case invalidRequest
    case invalidResponse
    case invalidData
    case requestFailed(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The podcast search could not be created."
        case .invalidResponse:
            return "Podcast Index returned an invalid response."
        case .invalidData:
            return "Podcast Index returned search results the app could not read."
        case .requestFailed(let statusCode):
            return "Podcast search failed with HTTP \(statusCode)."
        }
    }
}

private extension PodcastIndexSearchService {
    struct SearchResponse: Decodable {
        let results: [SearchResult]
    }

    struct SearchResult: Decodable {
        let artistName: String?
        let collectionName: String?
        let trackName: String?
        let feedURL: String?
        let artworkURL100: String?
        let artworkURL600: String?
        let trackCount: Int?
        let collectionExplicitness: String?

        private enum CodingKeys: String, CodingKey {
            case artistName
            case collectionName
            case trackName
            case feedURL = "feedUrl"
            case artworkURL100 = "artworkUrl100"
            case artworkURL600 = "artworkUrl600"
            case trackCount
            case collectionExplicitness
        }
    }
}
