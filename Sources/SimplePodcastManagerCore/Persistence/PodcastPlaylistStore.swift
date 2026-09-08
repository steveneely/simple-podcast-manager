import Foundation

public protocol PodcastPlaylistStore: Sendable {
    func loadPodcastPlaylistLibrary() throws -> PodcastPlaylistLibrary
    func savePodcastPlaylistLibrary(_ library: PodcastPlaylistLibrary) throws
}
