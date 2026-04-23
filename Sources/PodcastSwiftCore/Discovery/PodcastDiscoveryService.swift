import Foundation

public protocol PodcastDiscoveryService: Sendable {
    func searchPodcasts(matching query: String) async throws -> [DiscoveryResult]
}
