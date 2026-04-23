import Foundation

public enum EpisodeFileName {
    public static func fileName(for episode: Episode, fileExtension: String) -> String {
        let normalizedExtension = fileExtension.isEmpty ? "bin" : fileExtension.lowercased()
        return fileStem(for: episode) + "." + normalizedExtension
    }

    public static func fileStem(for episode: Episode) -> String {
        let title = sanitizedComponent(episode.title)
        let podcastTitle = sanitizedComponent(episode.podcastTitle)
        let fallbackStem = episode.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : episode.id

        var stem = ""
        if let publicationDate = episode.publicationDate {
            stem += dateFormatter.string(from: publicationDate) + "-"
        }

        if !title.isEmpty {
            stem += title
        } else if !podcastTitle.isEmpty {
            stem += podcastTitle
        } else {
            stem += fallbackStem
        }

        if !podcastTitle.isEmpty {
            stem += "-(\(podcastTitle))"
        }

        return stem
    }

    public static func publicationDate(from fileURL: URL) -> Date? {
        let fileName = fileURL.lastPathComponent
        guard fileName.count >= 11 else { return nil }

        let prefixEndIndex = fileName.index(fileName.startIndex, offsetBy: 10)
        guard prefixEndIndex < fileName.endIndex, fileName[prefixEndIndex] == "-" else { return nil }

        let datePrefix = String(fileName[..<prefixEndIndex])
        return dateFormatter.date(from: datePrefix)
    }

    public static func isMetadataSidecar(_ fileURL: URL) -> Bool {
        fileURL.lastPathComponent.hasPrefix("._")
    }

    private static func sanitizedComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let disallowed = CharacterSet(charactersIn: "/:\\?%*\"<>")
        let components = trimmed.components(separatedBy: disallowed)
        let collapsed = components
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return collapsed.isEmpty ? "" : collapsed
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()
}
