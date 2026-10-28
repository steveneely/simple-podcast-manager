import Foundation
import SimplePodcastManagerCore

/// A fixed episode order keeps range selection stable while downloads finish in the background.
struct PodcastEpisodeDownloadSelection {
    let episodes: [Episode]
    private(set) var selectedIDs: Set<Episode.ID> = []
    private var anchorID: Episode.ID?

    init(episodes: [Episode]) {
        self.episodes = episodes
    }

    func selectedEpisodes(unavailableIDs: Set<Episode.ID>) -> [Episode] {
        episodes.filter { selectedIDs.contains($0.id) && !unavailableIDs.contains($0.id) }
    }

    func areAllSelected(unavailableIDs: Set<Episode.ID>) -> Bool {
        let availableEpisodes = episodes.filter { !unavailableIDs.contains($0.id) }
        return !availableEpisodes.isEmpty && availableEpisodes.allSatisfy { selectedIDs.contains($0.id) }
    }

    mutating func setAllSelected(_ isSelected: Bool, unavailableIDs: Set<Episode.ID>) {
        if isSelected {
            selectAll(unavailableIDs: unavailableIDs)
        } else {
            deselectAll()
        }
    }

    mutating func selectAll(unavailableIDs: Set<Episode.ID>) {
        selectedIDs = Set(episodes.map(\.id)).subtracting(unavailableIDs)
        anchorID = nil
    }

    mutating func deselectAll() {
        selectedIDs.removeAll()
        anchorID = nil
    }

    mutating func setSelected(
        _ isSelected: Bool,
        episodeID: Episode.ID,
        extendingRange: Bool,
        unavailableIDs: Set<Episode.ID>
    ) {
        guard !unavailableIDs.contains(episodeID),
              let index = episodes.firstIndex(where: { $0.id == episodeID }) else { return }

        let affectedIDs: Set<Episode.ID>
        if extendingRange, let anchorID,
           let anchorIndex = episodes.firstIndex(where: { $0.id == anchorID }) {
            affectedIDs = Set(episodes[min(index, anchorIndex)...max(index, anchorIndex)].map(\.id))
                .subtracting(unavailableIDs)
        } else {
            affectedIDs = [episodeID]
            anchorID = episodeID
        }

        if isSelected {
            selectedIDs.formUnion(affectedIDs)
        } else {
            selectedIDs.subtract(affectedIDs)
        }
        selectedIDs.subtract(unavailableIDs)
    }
}

struct PodcastEpisodeDownloadPresentation: Identifiable {
    let id = UUID()
    let podcastTitle: String
    let episodes: [Episode]
}
