import Foundation
import Observation
import SimplePodcastManagerCore

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
        removedRecord(for: episode)?.removedAt
    }

    public func removedRecord(for episode: Episode) -> RemovedEpisodeRecord? {
        guard let subscriptionID = episode.subscriptionID else { return nil }
        let fileStem = EpisodeFileName.fileStem(for: episode)
        return removedEpisodes.first(where: {
            guard $0.subscriptionID == subscriptionID else { return false }
            if let episodeID = $0.episodeID, episodeID == episode.id {
                return true
            }
            return $0.fileStem == fileStem
        })
    }

    public func recordDeletedEpisodes(
        deletedTargetURLs: [URL],
        filesBySubscriptionID: [UUID: [URL]],
        episodesBySubscriptionID: [UUID: [Episode]],
        deviceName: String?,
        removedAt: Date
    ) {
        guard !deletedTargetURLs.isEmpty else { return }

        var recordsByID = Dictionary(uniqueKeysWithValues: removedEpisodes.map { ($0.id, $0) })

        for targetURL in deletedTargetURLs.map(\.standardizedFileURL) {
            guard
                let subscriptionID = filesBySubscriptionID.first(where: { _, files in
                    files.map(\.standardizedFileURL).contains(targetURL)
                })?.key
            else {
                continue
            }

            let targetFileStem = targetURL.deletingPathExtension().lastPathComponent
            let matchedEpisode = episodesBySubscriptionID[subscriptionID]?.first(where: {
                EpisodeFileName.fileStem(for: $0) == targetFileStem
            })
            let parsedMetadata = EpisodeFileName.parsedMetadata(from: targetURL)

            let record = RemovedEpisodeRecord(
                subscriptionID: subscriptionID,
                episodeID: matchedEpisode?.id,
                fileStem: targetFileStem,
                episodeTitle: matchedEpisode?.title ?? parsedMetadata?.episodeTitle ?? targetFileStem,
                publicationDate: matchedEpisode?.publicationDate ?? parsedMetadata?.publicationDate,
                deviceName: deviceName,
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
