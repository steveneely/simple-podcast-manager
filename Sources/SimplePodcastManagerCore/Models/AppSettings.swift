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

public enum InactivePodcastThreshold: String, Codable, Equatable, Sendable, CaseIterable {
    case off
    case threeMonths
    case sixMonths
    case oneYear

    public var monthCount: Int? {
        switch self {
        case .off: nil
        case .threeMonths: 3
        case .sixMonths: 6
        case .oneYear: 12
        }
    }
}

public struct DeviceCleanupPolicy: Codable, Equatable, Sendable {
    public static let allowedMaximumEpisodesPerShow = [3, 5, 10, 20]

    public var maximumEpisodesPerShow: Int?

    public init(maximumEpisodesPerShow: Int? = nil) {
        self.maximumEpisodesPerShow = maximumEpisodesPerShow
    }

    public var isEnabled: Bool {
        maximumEpisodesPerShow != nil
    }

}

public struct AppSettings: Codable, Equatable, Sendable {
    public var ffmpegExecutablePath: String?
    public var appearancePreference: AppearancePreference
    public var allowsInsecureDownloads: Bool
    public var prefixesPublicationDateInEpisodeTitles: Bool
    public var automaticDownloadLimit: AutomaticDownloadLimit
    public var deviceCleanupPolicy: DeviceCleanupPolicy
    public var inactivePodcastThreshold: InactivePodcastThreshold

    public init(
        ffmpegExecutablePath: String? = nil,
        appearancePreference: AppearancePreference = .system,
        allowsInsecureDownloads: Bool = false,
        prefixesPublicationDateInEpisodeTitles: Bool = false,
        automaticDownloadLimit: AutomaticDownloadLimit = .off,
        deviceCleanupPolicy: DeviceCleanupPolicy = DeviceCleanupPolicy(),
        inactivePodcastThreshold: InactivePodcastThreshold = .sixMonths
    ) {
        self.ffmpegExecutablePath = ffmpegExecutablePath
        self.appearancePreference = appearancePreference
        self.allowsInsecureDownloads = allowsInsecureDownloads
        self.prefixesPublicationDateInEpisodeTitles = prefixesPublicationDateInEpisodeTitles
        self.automaticDownloadLimit = automaticDownloadLimit
        self.deviceCleanupPolicy = deviceCleanupPolicy
        self.inactivePodcastThreshold = inactivePodcastThreshold
    }

    private enum CodingKeys: String, CodingKey {
        case ffmpegExecutablePath
        case appearancePreference
        case allowsInsecureDownloads
        case allowsInsecureEpisodeDownloads
        case prefixesPublicationDateInEpisodeTitles
        case automaticDownloadLimit
        case deviceCleanupPolicy
        case inactivePodcastThreshold
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
        inactivePodcastThreshold = try container.decodeIfPresent(
            InactivePodcastThreshold.self,
            forKey: .inactivePodcastThreshold
        ) ?? .sixMonths
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ffmpegExecutablePath, forKey: .ffmpegExecutablePath)
        try container.encode(appearancePreference, forKey: .appearancePreference)
        try container.encode(allowsInsecureDownloads, forKey: .allowsInsecureDownloads)
        try container.encode(prefixesPublicationDateInEpisodeTitles, forKey: .prefixesPublicationDateInEpisodeTitles)
        try container.encode(automaticDownloadLimit, forKey: .automaticDownloadLimit)
        try container.encode(deviceCleanupPolicy, forKey: .deviceCleanupPolicy)
        try container.encode(inactivePodcastThreshold, forKey: .inactivePodcastThreshold)
    }
}
