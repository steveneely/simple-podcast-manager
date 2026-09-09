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
    public func createPlaylist(
        named name: String,
        automaticRule: PodcastPlaylistAutomaticRule? = nil
    ) throws -> PodcastPlaylist.ID {
        var updatedLibrary = library
        if let automaticRule {
            try validate(automaticRule)
        }
        let playlist = try PodcastPlaylist(name: name, automaticRule: automaticRule)
        try ensureUniqueName(playlist.name, excluding: nil, in: updatedLibrary.playlists)
        updatedLibrary.playlists.append(playlist)
        try persist(updatedLibrary)
        return playlist.id
    }

    public func renamePlaylist(id: PodcastPlaylist.ID, to name: String) throws {
        var updatedLibrary = library
        guard let index = updatedLibrary.playlists.firstIndex(where: { $0.id == id }) else { return }
        guard try applyName(name, toPlaylistAt: index, in: &updatedLibrary) else { return }
        try persist(updatedLibrary)
    }

    public func updatePlaylist(
        id: PodcastPlaylist.ID,
        name: String,
        automaticRule: PodcastPlaylistAutomaticRule?
    ) throws {
        if let automaticRule {
            try validate(automaticRule)
        }
        var updatedLibrary = library
        guard let index = updatedLibrary.playlists.firstIndex(where: { $0.id == id }) else { return }
        try applyName(name, toPlaylistAt: index, in: &updatedLibrary)
        updatedLibrary.playlists[index].automaticRule = automaticRule
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

    public func add(
        _ episode: Episode,
        to playlistID: PodcastPlaylist.ID,
        deviceFileURL: URL? = nil
    ) throws {
        guard let entry = PodcastPlaylistEntry(episode: episode) else {
            throw PodcastPlaylistError.missingEpisodeIdentity
        }
        var updatedLibrary = library
        guard let index = updatedLibrary.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        guard !updatedLibrary.playlists[index].entries.contains(where: { $0.id == entry.id }) else { return }
        updatedLibrary.playlists[index].entries.append(entry)
        for exclusion in automaticExclusions(for: episode, deviceFileURL: deviceFileURL) {
            updatedLibrary.playlists[index].automaticExclusions.remove(exclusion)
        }
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

    public func excludeAutomaticEpisode(
        _ episode: Episode,
        from playlistID: PodcastPlaylist.ID,
        deviceFileURL: URL? = nil
    ) throws {
        let exclusions = automaticExclusions(for: episode, deviceFileURL: deviceFileURL)
        guard !exclusions.isEmpty else {
            throw PodcastPlaylistError.missingEpisodeIdentity
        }
        var updatedLibrary = library
        guard let index = updatedLibrary.playlists.firstIndex(where: { $0.id == playlistID }),
              updatedLibrary.playlists[index].automaticRule != nil else { return }
        updatedLibrary.playlists[index].automaticExclusions.formUnion(exclusions)
        try persist(updatedLibrary)
    }

    public func moveEntry(
        in playlistID: PodcastPlaylist.ID,
        from sourceIndex: Int,
        to destinationIndex: Int
    ) throws {
        var updatedLibrary = library
        guard let playlistIndex = updatedLibrary.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        guard updatedLibrary.playlists[playlistIndex].entries.indices.contains(sourceIndex) else { return }
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
            updatedLibrary.playlists[index].automaticExclusions = updatedLibrary.playlists[index]
                .automaticExclusions.filter { !subscriptionIDs.contains($0.subscriptionID) }
            guard var automaticRule = updatedLibrary.playlists[index].automaticRule,
                  case .selectedPodcasts(var includedPodcastIDs) = automaticRule.source else { continue }
            includedPodcastIDs.subtract(subscriptionIDs)
            automaticRule.source = .selectedPodcasts(includedPodcastIDs)
            updatedLibrary.playlists[index].automaticRule = automaticRule
        }
        for deviceID in Array(updatedLibrary.deviceStates.keys) {
            updatedLibrary.deviceStates[deviceID]?.mostRecentSyncEntries.removeAll {
                subscriptionIDs.contains($0.id.subscriptionID)
            }
        }
        updatedLibrary.recentlyDownloadedEntries.removeAll {
            subscriptionIDs.contains($0.id.subscriptionID)
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
        updatedLibrary.recentlyDownloadedEntries.removeAll { entryIDs.contains($0.id) }
        try persist(updatedLibrary)
    }

    public func recordDownloadedEpisodes(_ episodes: [Episode]) throws {
        guard isLoaded else { return }
        var seenEntryIDs: Set<PodcastPlaylistEpisodeID> = []
        let newEntries = episodes.compactMap { episode -> PodcastPlaylistEntry? in
            guard let entry = PodcastPlaylistEntry(episode: episode),
                  seenEntryIDs.insert(entry.id).inserted else { return nil }
            return entry
        }
        guard !newEntries.isEmpty else { return }

        var updatedLibrary = library
        let newEntryIDs = Set(newEntries.map(\.id))
        updatedLibrary.recentlyDownloadedEntries.removeAll { newEntryIDs.contains($0.id) }
        updatedLibrary.recentlyDownloadedEntries.insert(contentsOf: newEntries, at: 0)
        try persist(updatedLibrary)
    }

    public func seedRecentlyDownloadedEpisodes(_ episodes: [Episode]) throws {
        guard isLoaded else { return }
        let knownEntryIDs = Set(library.recentlyDownloadedEntries.map(\.id))
        var seenEntryIDs = knownEntryIDs
        let missingEntries = episodes.compactMap { episode -> PodcastPlaylistEntry? in
            guard let entry = PodcastPlaylistEntry(episode: episode),
                  seenEntryIDs.insert(entry.id).inserted else { return nil }
            return entry
        }
        guard !missingEntries.isEmpty else { return }

        var updatedLibrary = library
        updatedLibrary.recentlyDownloadedEntries.append(contentsOf: missingEntries)
        try persist(updatedLibrary)
    }

    public func playlists(containing episode: Episode) -> [PodcastPlaylist] {
        guard let entryID = PodcastPlaylistEpisodeID(episode: episode) else { return [] }
        let recentlyDownloadedEpisodes = library.recentlyDownloadedEntries.map(\.episode)
        return library.playlists.filter { playlist in
            if playlist.contains(episode) {
                return true
            }
            guard playlist.automaticRule?.source == .recentlyDownloaded else { return false }
            return PodcastPlaylistResolver.entries(
                for: playlist,
                from: recentlyDownloadedEpisodes,
                recentlyDownloadedEntries: library.recentlyDownloadedEntries
            ).automatic.contains { $0.id == entryID }
        }
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

    @discardableResult
    private func applyName(
        _ name: String,
        toPlaylistAt index: Int,
        in library: inout PodcastPlaylistLibrary
    ) throws -> Bool {
        let playlistID = library.playlists[index].id
        let validatedName = try PodcastPlaylistName.validated(name)
        try ensureUniqueName(validatedName, excluding: playlistID, in: library.playlists)
        guard library.playlists[index].name != validatedName else { return false }

        let previousFileName = library.playlists[index].deviceFileName
        let updatedFileName = PodcastPlaylistName.deviceFileName(for: validatedName)
        if previousFileName != updatedFileName {
            for deviceID in Array(library.deviceStates.keys) {
                guard library.deviceStates[deviceID]?.ownedDeviceFileNames.contains(previousFileName) == true else { continue }
                library.deviceStates[deviceID]?.pendingDeletedDeviceFileNames.insert(previousFileName)
            }
        }
        library.playlists[index].name = validatedName
        library.playlists[index].deviceFileName = updatedFileName
        return true
    }

    private func validate(_ rule: PodcastPlaylistAutomaticRule) throws {
        guard case .selectedPodcasts(let includedPodcastIDs) = rule.source else {
            throw PodcastPlaylistError.unsupportedAutomaticPlaylistSource
        }
        if includedPodcastIDs.isEmpty {
            throw PodcastPlaylistError.automaticPlaylistNeedsPodcast
        }
        if let maximumEpisodeCount = rule.maximumEpisodeCount,
           maximumEpisodeCount <= 0 {
            throw PodcastPlaylistError.invalidAutomaticPlaylistLimit
        }
    }

    private func automaticExclusions(
        for episode: Episode,
        deviceFileURL: URL?
    ) -> Set<PodcastPlaylistAutomaticExclusion> {
        guard let subscriptionID = episode.subscriptionID else { return [] }
        var exclusions: Set<PodcastPlaylistAutomaticExclusion> = [
            PodcastPlaylistAutomaticExclusion(
                subscriptionID: subscriptionID,
                episodeFileStem: EpisodeFileName.fileStem(for: episode)
            )
        ]
        if let deviceFileURL {
            exclusions.insert(PodcastPlaylistAutomaticExclusion(
                subscriptionID: subscriptionID,
                episodeFileStem: deviceFileURL.deletingPathExtension().lastPathComponent
            ))
        }
        return exclusions
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
