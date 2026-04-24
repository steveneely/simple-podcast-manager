import Foundation
import Observation
import SPodcastManagerCore

@MainActor
@Observable
public final class RemovedEpisodeHistoryViewModel {
    public private(set) var removedEpisodes: [RemovedEpisodeRecord]
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedRemovedEpisodes: Bool

    private let store: any RemovedEpisodeStore

    public init(store: any RemovedEpisodeStore = JSONRemovedEpisodeStore(fileURL: JSONRemovedEpisodeStore.defaultFileURL())) {
        self.store = store
        self.removedEpisodes = []
        self.lastErrorMessage = nil
        self.hasLoadedRemovedEpisodes = false
    }

    public func load() {
        do {
            removedEpisodes = try store.loadRemovedEpisodes()
                .sorted { lhs, rhs in
                    if lhs.removedAt != rhs.removedAt {
                        return lhs.removedAt > rhs.removedAt
                    }
                    return lhs.episodeTitle.localizedCaseInsensitiveCompare(rhs.episodeTitle) == .orderedAscending
                }
            hasLoadedRemovedEpisodes = true
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func removedAt(for episode: Episode) -> Date? {
        guard let subscriptionID = episode.subscriptionID else { return nil }
        return removedEpisodes.first(where: {
            $0.subscriptionID == subscriptionID && $0.episodeID == episode.id
        })?.removedAt
    }

    public func recordDeletedEpisodes(
        deletedTargetURLs: [URL],
        filesBySubscriptionID: [UUID: [URL]],
        episodesBySubscriptionID: [UUID: [Episode]],
        removedAt: Date
    ) {
        guard !deletedTargetURLs.isEmpty else { return }

        var recordsByID = Dictionary(uniqueKeysWithValues: removedEpisodes.map { ($0.id, $0) })

        for targetURL in deletedTargetURLs.map(\.standardizedFileURL) {
            guard
                let subscriptionID = filesBySubscriptionID.first(where: { _, files in
                    files.map(\.standardizedFileURL).contains(targetURL)
                })?.key,
                let episode = episodesBySubscriptionID[subscriptionID]?.first(where: {
                    EpisodeFileName.fileStem(for: $0) == targetURL.deletingPathExtension().lastPathComponent
                })
            else {
                continue
            }

            let record = RemovedEpisodeRecord(
                subscriptionID: subscriptionID,
                episodeID: episode.id,
                episodeTitle: episode.title,
                publicationDate: episode.publicationDate,
                removedAt: removedAt
            )
            recordsByID[record.id] = record
        }

        removedEpisodes = recordsByID.values.sorted { lhs, rhs in
            if lhs.removedAt != rhs.removedAt {
                return lhs.removedAt > rhs.removedAt
            }
            return lhs.episodeTitle.localizedCaseInsensitiveCompare(rhs.episodeTitle) == .orderedAscending
        }
        persist()
    }

    private func persist() {
        do {
            try store.saveRemovedEpisodes(removedEpisodes)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
