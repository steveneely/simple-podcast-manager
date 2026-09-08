import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class PodcastPlaylistViewModel {
    public private(set) var library: PodcastPlaylistLibrary
    public private(set) var isLoaded: Bool
    public private(set) var lastErrorMessage: String?

    private let store: any PodcastPlaylistStore

    public init(store: any PodcastPlaylistStore = SQLiteEpisodeStore.shared) {
        self.store = store
        self.library = PodcastPlaylistLibrary()
        self.isLoaded = false
    }

    public var playlists: [PodcastPlaylist] {
        library.playlists
    }

    public func load() async {
        do {
            let store = self.store
            let loadedLibrary = try await Task.detached(priority: .userInitiated) {
                try store.loadPodcastPlaylistLibrary()
            }.value
            library = loadedLibrary
            isLoaded = true
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = Self.message(for: error)
        }
    }

    @discardableResult
    public func createPlaylist(named name: String) throws -> PodcastPlaylist.ID {
        var updatedLibrary = library
        let playlist = try PodcastPlaylist(name: name)
        try ensureUniqueName(playlist.name, excluding: nil, in: updatedLibrary.playlists)
        updatedLibrary.playlists.append(playlist)
        try persist(updatedLibrary)
        return playlist.id
    }

    public func renamePlaylist(id: PodcastPlaylist.ID, to name: String) throws {
        var updatedLibrary = library
        guard let index = updatedLibrary.playlists.firstIndex(where: { $0.id == id }) else { return }
        let validatedName = try PodcastPlaylistName.validated(name)
        try ensureUniqueName(validatedName, excluding: id, in: updatedLibrary.playlists)
        guard updatedLibrary.playlists[index].name != validatedName else { return }

        let previousFileName = updatedLibrary.playlists[index].deviceFileName
        let updatedFileName = PodcastPlaylistName.deviceFileName(for: validatedName)
        if previousFileName != updatedFileName {
            for deviceID in Array(updatedLibrary.deviceStates.keys) {
                guard updatedLibrary.deviceStates[deviceID]?.ownedDeviceFileNames.contains(previousFileName) == true else { continue }
                updatedLibrary.deviceStates[deviceID]?.pendingDeletedDeviceFileNames.insert(previousFileName)
            }
        }
        updatedLibrary.playlists[index].name = validatedName
        updatedLibrary.playlists[index].deviceFileName = updatedFileName
        try persist(updatedLibrary)
    }

    public func deletePlaylist(id: PodcastPlaylist.ID) throws {
        var updatedLibrary = library
        guard let playlist = updatedLibrary.playlists.first(where: { $0.id == id }) else { return }
        for deviceID in Array(updatedLibrary.deviceStates.keys) {
            guard updatedLibrary.deviceStates[deviceID]?.ownedDeviceFileNames.contains(playlist.deviceFileName) == true else { continue }
            updatedLibrary.deviceStates[deviceID]?.pendingDeletedDeviceFileNames.insert(playlist.deviceFileName)
        }
        updatedLibrary.playlists.removeAll { $0.id == id }
        try persist(updatedLibrary)
    }

    public func add(_ episode: Episode, to playlistID: PodcastPlaylist.ID) throws {
        guard let entry = PodcastPlaylistEntry(episode: episode) else {
            throw PodcastPlaylistError.missingEpisodeIdentity
        }
        var updatedLibrary = library
        guard let index = updatedLibrary.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        guard !updatedLibrary.playlists[index].entries.contains(where: { $0.id == entry.id }) else { return }
        updatedLibrary.playlists[index].entries.append(entry)
        try persist(updatedLibrary)
    }

    public func remove(_ episode: Episode, from playlistID: PodcastPlaylist.ID) throws {
        guard let entryID = PodcastPlaylistEpisodeID(episode: episode) else { return }
        try remove(entryID, from: playlistID)
    }

    public func remove(_ entryID: PodcastPlaylistEpisodeID, from playlistID: PodcastPlaylist.ID) throws {
        var updatedLibrary = library
        guard let index = updatedLibrary.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        updatedLibrary.playlists[index].entries.removeAll { $0.id == entryID }
        try persist(updatedLibrary)
    }

    public func moveEntry(
        in playlistID: PodcastPlaylist.ID,
        from sourceIndex: Int,
        to destinationIndex: Int
    ) throws {
        var updatedLibrary = library
        guard let playlistIndex = updatedLibrary.playlists.firstIndex(where: { $0.id == playlistID }),
              updatedLibrary.playlists[playlistIndex].entries.indices.contains(sourceIndex) else { return }
        let entry = updatedLibrary.playlists[playlistIndex].entries.remove(at: sourceIndex)
        let insertionIndex = min(max(destinationIndex, 0), updatedLibrary.playlists[playlistIndex].entries.count)
        updatedLibrary.playlists[playlistIndex].entries.insert(entry, at: insertionIndex)
        try persist(updatedLibrary)
    }

    public func moveEntries(
        in playlistID: PodcastPlaylist.ID,
        from sourceIndexes: IndexSet,
        to destinationIndex: Int
    ) throws {
        var updatedLibrary = library
        guard let playlistIndex = updatedLibrary.playlists.firstIndex(where: { $0.id == playlistID }) else {
            return
        }
        var entries = updatedLibrary.playlists[playlistIndex].entries
        let validSourceIndexes = sourceIndexes.sorted().filter(entries.indices.contains)
        guard !validSourceIndexes.isEmpty else { return }

        let movingEntries = validSourceIndexes.map { entries[$0] }
        for sourceIndex in validSourceIndexes.reversed() {
            entries.remove(at: sourceIndex)
        }
        let removedBeforeDestination = validSourceIndexes.count { $0 < destinationIndex }
        let insertionIndex = min(max(destinationIndex - removedBeforeDestination, 0), entries.count)
        entries.insert(contentsOf: movingEntries, at: insertionIndex)
        updatedLibrary.playlists[playlistIndex].entries = entries
        try persist(updatedLibrary)
    }

    public func removeEntries(forSubscriptionIDs subscriptionIDs: Set<UUID>) throws {
        guard !subscriptionIDs.isEmpty else { return }
        var updatedLibrary = library
        for index in updatedLibrary.playlists.indices {
            updatedLibrary.playlists[index].entries.removeAll {
                subscriptionIDs.contains($0.id.subscriptionID)
            }
        }
        try persist(updatedLibrary)
    }

    public func removeFromAllPlaylists(_ episode: Episode) throws {
        guard let entryID = PodcastPlaylistEpisodeID(episode: episode) else { return }
        try removeFromAllPlaylists(entryIDs: [entryID])
    }

    public func removeFromAllPlaylists(entryIDs: Set<PodcastPlaylistEpisodeID>) throws {
        guard !entryIDs.isEmpty else { return }
        var updatedLibrary = library
        for index in updatedLibrary.playlists.indices {
            updatedLibrary.playlists[index].entries.removeAll { entryIDs.contains($0.id) }
        }
        try persist(updatedLibrary)
    }

    public func playlists(containing episode: Episode) -> [PodcastPlaylist] {
        library.playlists.filter { $0.contains(episode) }
    }

    public func playlist(id: PodcastPlaylist.ID?) -> PodcastPlaylist? {
        guard let id else { return nil }
        return library.playlists.first { $0.id == id }
    }

    public func markDevicePlaylistSyncCompleted(deviceID: String) throws {
        var updatedLibrary = library
        updatedLibrary.deviceStates[deviceID] = PodcastPlaylistDeviceState(
            ownedDeviceFileNames: Set(updatedLibrary.playlists.map(\.deviceFileName)),
            pendingDeletedDeviceFileNames: []
        )
        try persist(updatedLibrary)
    }

    private func ensureUniqueName(
        _ name: String,
        excluding excludedID: PodcastPlaylist.ID?,
        in playlists: [PodcastPlaylist]
    ) throws {
        let normalizedName = PodcastPlaylistName.normalized(name)
        if playlists.contains(where: {
            $0.id != excludedID && PodcastPlaylistName.normalized($0.name) == normalizedName
        }) {
            throw PodcastPlaylistError.duplicateName
        }
    }

    private func persist(_ updatedLibrary: PodcastPlaylistLibrary) throws {
        do {
            try store.savePodcastPlaylistLibrary(updatedLibrary)
            library = updatedLibrary
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = Self.message(for: error)
            throw error
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
