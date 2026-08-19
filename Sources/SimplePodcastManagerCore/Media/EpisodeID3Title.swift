import Foundation

public enum EpisodeID3Title {
    public static func title(
        for episode: Episode,
        prefixesPublicationDate: Bool
    ) -> String {
        guard prefixesPublicationDate, let publicationDate = episode.publicationDate else {
            return episode.title
        }

        return "\(dateFormatter.string(from: publicationDate)) \(episode.title)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM.dd"
        return formatter
    }()
}
