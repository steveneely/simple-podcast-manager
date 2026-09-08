import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct PodcastPlaylistViewModelTests {
    @Test
    func createsOrdersAndRemovesPlaylistEntries() async throws {
        let store = InMemoryPodcastPlaylistStore()
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()
        let playlistID = try viewModel.createPlaylist(named: "Commute")
        let first = makeEpisode(id: "first", title: "First")
        let second = makeEpisode(id: "second", title: "Second")

        try viewModel.add(first, to: playlistID)
        try viewModel.add(second, to: playlistID)
        try viewModel.moveEntry(in: playlistID, from: 1, to: 0)
        try viewModel.remove(first, from: playlistID)

        #expect(viewModel.playlist(id: playlistID)?.entries.map(\.episode.id) == ["second"])
        #expect(store.library == viewModel.library)
    }

    @Test
    func dragMovePreservesTheRelativeOrderOfMovedEntries() async throws {
        let store = InMemoryPodcastPlaylistStore()
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()
        let playlistID = try viewModel.createPlaylist(named: "Commute")
        for id in ["first", "second", "third", "fourth"] {
            try viewModel.add(makeEpisode(id: id, title: id.capitalized), to: playlistID)
        }

        try viewModel.moveEntries(in: playlistID, from: IndexSet([1, 2]), to: 4)

        #expect(viewModel.playlist(id: playlistID)?.entries.map(\.episode.id) == [
            "first", "fourth", "second", "third",
        ])
    }

    @Test
    func renameKeepsOldOwnedFileAsDeletionTombstoneUntilSyncCompletes() async throws {
        let original = try PodcastPlaylist(name: "Commute")
        let store = InMemoryPodcastPlaylistStore(library: PodcastPlaylistLibrary(
            playlists: [original],
            deviceStates: [
                "walkman": PodcastPlaylistDeviceState(ownedDeviceFileNames: ["Commute.m3u"])
            ]
        ))
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()

        try viewModel.renamePlaylist(id: original.id, to: "Garden")

        #expect(viewModel.library.deviceStates["walkman"]?.pendingDeletedDeviceFileNames == ["Commute.m3u"])
        try viewModel.markDevicePlaylistSyncCompleted(deviceID: "walkman")
        #expect(viewModel.library.deviceStates["walkman"] == PodcastPlaylistDeviceState(
            ownedDeviceFileNames: ["Garden.m3u"],
            pendingDeletedDeviceFileNames: []
        ))
    }

    @Test
    func rejectsDuplicateNamesCaseInsensitively() async throws {
        let store = InMemoryPodcastPlaylistStore()
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()
        _ = try viewModel.createPlaylist(named: "Commute")

        #expect(throws: PodcastPlaylistError.duplicateName) {
            try viewModel.createPlaylist(named: "commute")
        }
    }

    private func makeEpisode(id: String, title: String) -> Episode {
        Episode(
            id: id,
            subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            podcastTitle: "Example Podcast",
            title: title,
            enclosureURL: URL(string: "https://example.com/\(id).mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
    }
}

private final class InMemoryPodcastPlaylistStore: PodcastPlaylistStore, @unchecked Sendable {
    var library: PodcastPlaylistLibrary

    init(library: PodcastPlaylistLibrary = PodcastPlaylistLibrary()) {
        self.library = library
    }

    func loadPodcastPlaylistLibrary() throws -> PodcastPlaylistLibrary {
        library
    }

    func savePodcastPlaylistLibrary(_ library: PodcastPlaylistLibrary) throws {
        self.library = library
    }
}
