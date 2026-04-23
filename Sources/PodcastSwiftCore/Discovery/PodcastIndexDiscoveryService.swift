import CryptoKit
import Foundation

public struct PodcastIndexDiscoveryService: PodcastDiscoveryService {
    public let credentials: PodcastDirectoryCredentials
    public let session: URLSession
    public let baseURL: URL
    public let userAgent: String
    private let dateProvider: @Sendable () -> Date

    public init(
        credentials: PodcastDirectoryCredentials,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.podcastindex.org/api/1.0")!,
        userAgent: String = "PodcastSwift/0.1",
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentials = credentials
        self.session = session
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.dateProvider = dateProvider
    }

    public func searchPodcasts(matching query: String) async throws -> [DiscoveryResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            throw PodcastDiscoveryError.invalidSearchTerm
        }

        guard credentials.isValid else {
            throw PodcastDiscoveryError.missingCredentials
        }

        var components = URLComponents(url: baseURL.appending(path: "search/byterm", directoryHint: .notDirectory), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: normalizedQuery),
        ]

        guard let url = components?.url else {
            throw PodcastDiscoveryError.invalidResponse
        }

        let unixTimestamp = Self.unixTimestampString(from: dateProvider())
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-Auth-Key")
        request.setValue(unixTimestamp, forHTTPHeaderField: "X-Auth-Date")
        request.setValue(Self.authorizationHeader(credentials: credentials, unixTimestamp: unixTimestamp), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PodcastDiscoveryError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PodcastDiscoveryError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let decodedResponse = try JSONDecoder().decode(PodcastIndexSearchResponse.self, from: data)
        return decodedResponse.feeds.map { feed in
            DiscoveryResult(
                id: String(feed.id),
                title: feed.title,
                author: feed.author,
                summary: feed.description,
                artworkURL: URL(string: feed.artwork ?? ""),
                feedURL: URL(string: feed.url),
                source: "Podcast Index"
            )
        }
    }

    static func unixTimestampString(from date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }

    static func authorizationHeader(credentials: PodcastDirectoryCredentials, unixTimestamp: String) -> String {
        let input = credentials.apiKey + credentials.apiSecret + unixTimestamp
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct PodcastIndexSearchResponse: Decodable {
    let feeds: [PodcastIndexFeed]
}

private struct PodcastIndexFeed: Decodable {
    let id: Int
    let title: String
    let url: String
    let author: String?
    let description: String?
    let artwork: String?
}
