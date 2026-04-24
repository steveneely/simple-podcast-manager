import Foundation

public enum EpisodeFileName {
    public struct ParsedFileMetadata: Equatable, Sendable {
        public var fileStem: String
        public var episodeTitle: String
        public var podcastTitle: String?
        public var publicationDate: Date?

        public init(fileStem: String, episodeTitle: String, podcastTitle: String?, publicationDate: Date?) {
            self.fileStem = fileStem
            self.episodeTitle = episodeTitle
            self.podcastTitle = podcastTitle
            self.publicationDate = publicationDate
        }
    }

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
        parsedMetadata(from: fileURL)?.publicationDate
    }

    public static func parsedMetadata(from fileURL: URL) -> ParsedFileMetadata? {
        parsedMetadata(fromFileStem: fileURL.deletingPathExtension().lastPathComponent)
    }

    public static func isMetadataSidecar(_ fileURL: URL) -> Bool {
        fileURL.lastPathComponent.hasPrefix("._")
    }

    private static func parsedMetadata(fromFileStem fileStem: String) -> ParsedFileMetadata {
        var remainingStem = fileStem
        var publicationDate: Date?
        var podcastTitle: String?

        if remainingStem.count >= 11 {
            let prefixEndIndex = remainingStem.index(remainingStem.startIndex, offsetBy: 10)
            if prefixEndIndex < remainingStem.endIndex, remainingStem[prefixEndIndex] == "-" {
                let datePrefix = String(remainingStem[..<prefixEndIndex])
                publicationDate = dateFormatter.date(from: datePrefix)
                if publicationDate != nil {
                    remainingStem = String(remainingStem[remainingStem.index(after: prefixEndIndex)...])
                }
            }
        }

        if
            remainingStem.hasSuffix(")"),
            let openRange = remainingStem.range(of: "-(", options: .backwards)
        {
            podcastTitle = String(remainingStem[openRange.upperBound..<remainingStem.index(before: remainingStem.endIndex)])
            remainingStem = String(remainingStem[..<openRange.lowerBound])
        }

        return ParsedFileMetadata(
            fileStem: fileStem,
            episodeTitle: remainingStem,
            podcastTitle: podcastTitle,
            publicationDate: publicationDate
        )
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
