import Foundation

enum PublicationDateNormalizer {
    static func normalize(_ date: Date?) -> Date? {
        guard let date else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parsedYear = calendar.component(.year, from: date)
        let yearOffset: Int

        // RFC 822 allowed two-digit years. FeedKit's permissive formatter accepts
        // them with a four-digit pattern, which makes "26" year 26 instead of 2026.
        switch parsedYear {
        case 0...49:
            yearOffset = 2_000
        case 50...99:
            yearOffset = 1_900
        default:
            return date
        }

        return calendar.date(byAdding: .year, value: yearOffset, to: date) ?? date
    }

    static func normalize(_ episode: Episode) -> Episode {
        var normalizedEpisode = episode
        normalizedEpisode.publicationDate = normalize(episode.publicationDate)
        return normalizedEpisode
    }
}
