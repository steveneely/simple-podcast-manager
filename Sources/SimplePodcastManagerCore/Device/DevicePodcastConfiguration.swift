import Foundation

public struct DevicePodcastConfiguration: Equatable, Sendable {
    public static let fileName = ".spmconfig"
    public static let sectionName = "simple-podcast-manager"
    public static let defaultPodcastDirectoryPath = "music"
    public static let defaultConfiguration = DevicePodcastConfiguration(uncheckedPodcastDirectoryPath: defaultPodcastDirectoryPath)

    public var podcastDirectoryPath: String

    public init(podcastDirectoryPath: String = Self.defaultPodcastDirectoryPath) throws {
        self.podcastDirectoryPath = try Self.normalizedRelativeDirectoryPath(podcastDirectoryPath)
    }

    private init(uncheckedPodcastDirectoryPath: String) {
        self.podcastDirectoryPath = uncheckedPodcastDirectoryPath
    }

    public init(contents: String) throws {
        var isInAppSection = false
        var podcastDirectoryPath: String?

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                let section = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                isInAppSection = section == Self.sectionName
                continue
            }

            guard isInAppSection else { continue }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if key == "podcast-dir" {
                podcastDirectoryPath = value
            }
        }

        try self.init(podcastDirectoryPath: podcastDirectoryPath ?? Self.defaultPodcastDirectoryPath)
    }

    public var contents: String {
        """
        [\(Self.sectionName)]
        podcast-dir: \(podcastDirectoryPath)

        """
    }

    public static func normalizedRelativeDirectoryPath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return defaultPodcastDirectoryPath
        }

        guard !trimmed.hasPrefix("~"), !trimmed.hasPrefix("/") else {
            throw DevicePodcastConfigurationError.invalidPodcastDirectoryPath(path)
        }

        let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw DevicePodcastConfigurationError.invalidPodcastDirectoryPath(path)
        }

        return components.joined(separator: "/")
    }
}

public enum DevicePodcastConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case invalidPodcastDirectoryPath(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPodcastDirectoryPath:
            return "Podcast folder must be a relative path inside the device."
        }
    }
}
