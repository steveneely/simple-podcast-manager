public protocol PodcastSearching: Sendable {
    func searchPodcasts(matching query: String) async throws -> [PodcastSearchResult]
}
