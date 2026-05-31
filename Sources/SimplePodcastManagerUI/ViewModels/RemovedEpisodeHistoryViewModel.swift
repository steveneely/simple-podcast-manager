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
            if $0.fileStem == fileStem {
                return true
            }
            return Self.record($0, likelyMatches: episode)
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
            let parsedMetadata = EpisodeFileName.parsedMetadata(from: targetURL)
            let matchedEpisode = episodesBySubscriptionID[subscriptionID]?.first(where: {
                EpisodeFileName.fileStem(for: $0) == targetFileStem
                    || Self.episode($0, likelyMatchesDeletedFileStem: targetFileStem, parsedMetadata: parsedMetadata)
            })

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

    private static func record(_ record: RemovedEpisodeRecord, likelyMatches episode: Episode) -> Bool {
        guard samePublicationDay(record.publicationDate, episode.publicationDate) else {
            return false
        }

        let parsedMetadata = EpisodeFileName.parsedMetadata(fromFileStem: record.fileStem)
        return titlesLikelyMatch(record.episodeTitle, episode.title)
            || titlesLikelyMatch(parsedMetadata.episodeTitle, episode.title)
    }

    private static func episode(
        _ episode: Episode,
        likelyMatchesDeletedFileStem targetFileStem: String,
        parsedMetadata: EpisodeFileName.ParsedFileMetadata?
    ) -> Bool {
        guard samePublicationDay(parsedMetadata?.publicationDate, episode.publicationDate) else {
            return false
        }

        return titlesLikelyMatch(parsedMetadata?.episodeTitle ?? targetFileStem, episode.title)
    }

    private static func samePublicationDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "GMT")!
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }

    private static func titlesLikelyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let lhsTokens = significantTitleTokens(lhs)
        let rhsTokens = significantTitleTokens(rhs)
        guard lhsTokens.count >= 3, rhsTokens.count >= 3 else {
            return false
        }

        let overlapCount = lhsTokens.intersection(rhsTokens).count
        return overlapCount >= 4 || Double(overlapCount) / Double(min(lhsTokens.count, rhsTokens.count)) >= 0.45
    }

    private static func significantTitleTokens(_ title: String) -> Set<String> {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "at", "for", "from", "in", "is", "of", "on", "or", "the", "to", "with"
        ]
        let scalars = title
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .map { scalar -> Character in
                CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
            }

        return Set(
            String(scalars)
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { $0.count >= 3 && !stopWords.contains($0) }
        )
    }
}
