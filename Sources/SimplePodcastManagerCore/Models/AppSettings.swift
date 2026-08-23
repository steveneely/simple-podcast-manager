import Foundation

public enum AppearancePreference: String, Codable, Equatable, Sendable, CaseIterable {
    case system
    case light
    case dark
}

public enum AutomaticDownloadLimit: String, Codable, Equatable, Sendable, CaseIterable {
    case off
    case latest1
    case latest2
    case latest3
    case allNew

    public var maximumEpisodeCount: Int? {
        switch self {
        case .off:
            return 0
        case .latest1:
            return 1
        case .latest2:
            return 2
        case .latest3:
            return 3
        case .allNew:
            return nil
        }
    }
}

public struct DeviceCleanupPolicy: Codable, Equatable, Sendable {
    public static let defaultEpisodeAgeDays = 30
    public static let allowedEpisodeAgeDays = 1...3_650

    public var isEnabled: Bool
    public var episodeAgeDays: Int

    public init(
        isEnabled: Bool = false,
        episodeAgeDays: Int = Self.defaultEpisodeAgeDays
    ) {
        self.isEnabled = isEnabled
        self.episodeAgeDays = episodeAgeDays
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var ffmpegExecutablePath: String?
    public var appearancePreference: AppearancePreference
    public var allowsInsecureDownloads: Bool
    public var prefixesPublicationDateInEpisodeTitles: Bool
    public var automaticDownloadLimit: AutomaticDownloadLimit
    public var deviceCleanupPolicy: DeviceCleanupPolicy

    public init(
        ffmpegExecutablePath: String? = nil,
        appearancePreference: AppearancePreference = .system,
        allowsInsecureDownloads: Bool = false,
        prefixesPublicationDateInEpisodeTitles: Bool = false,
        automaticDownloadLimit: AutomaticDownloadLimit = .off,
        deviceCleanupPolicy: DeviceCleanupPolicy = DeviceCleanupPolicy()
    ) {
        self.ffmpegExecutablePath = ffmpegExecutablePath
        self.appearancePreference = appearancePreference
        self.allowsInsecureDownloads = allowsInsecureDownloads
        self.prefixesPublicationDateInEpisodeTitles = prefixesPublicationDateInEpisodeTitles
        self.automaticDownloadLimit = automaticDownloadLimit
        self.deviceCleanupPolicy = deviceCleanupPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case ffmpegExecutablePath
        case appearancePreference
        case allowsInsecureDownloads
        case allowsInsecureEpisodeDownloads
        case prefixesPublicationDateInEpisodeTitles
        case automaticDownloadLimit
        case deviceCleanupPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ffmpegExecutablePath = try container.decodeIfPresent(String.self, forKey: .ffmpegExecutablePath)
        appearancePreference = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearancePreference) ?? .system
        allowsInsecureDownloads = try container.decodeIfPresent(Bool.self, forKey: .allowsInsecureDownloads)
            ?? container.decodeIfPresent(Bool.self, forKey: .allowsInsecureEpisodeDownloads)
            ?? false
        prefixesPublicationDateInEpisodeTitles = try container.decodeIfPresent(
            Bool.self,
            forKey: .prefixesPublicationDateInEpisodeTitles
        ) ?? false
        automaticDownloadLimit = try container.decodeIfPresent(
            AutomaticDownloadLimit.self,
            forKey: .automaticDownloadLimit
        ) ?? .off
        deviceCleanupPolicy = try container.decodeIfPresent(
            DeviceCleanupPolicy.self,
            forKey: .deviceCleanupPolicy
        ) ?? DeviceCleanupPolicy()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ffmpegExecutablePath, forKey: .ffmpegExecutablePath)
        try container.encode(appearancePreference, forKey: .appearancePreference)
        try container.encode(allowsInsecureDownloads, forKey: .allowsInsecureDownloads)
        try container.encode(prefixesPublicationDateInEpisodeTitles, forKey: .prefixesPublicationDateInEpisodeTitles)
        try container.encode(automaticDownloadLimit, forKey: .automaticDownloadLimit)
        try container.encode(deviceCleanupPolicy, forKey: .deviceCleanupPolicy)
    }
}
