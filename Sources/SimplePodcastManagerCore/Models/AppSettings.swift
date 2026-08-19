import Foundation

public enum AppearancePreference: String, Codable, Equatable, Sendable, CaseIterable {
    case system
    case light
    case dark
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var ffmpegExecutablePath: String?
    public var appearancePreference: AppearancePreference
    public var allowsInsecureDownloads: Bool

    public init(
        ffmpegExecutablePath: String? = nil,
        appearancePreference: AppearancePreference = .system,
        allowsInsecureDownloads: Bool = false
    ) {
        self.ffmpegExecutablePath = ffmpegExecutablePath
        self.appearancePreference = appearancePreference
        self.allowsInsecureDownloads = allowsInsecureDownloads
    }

    private enum CodingKeys: String, CodingKey {
        case ffmpegExecutablePath
        case appearancePreference
        case allowsInsecureDownloads
        case allowsInsecureEpisodeDownloads
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ffmpegExecutablePath = try container.decodeIfPresent(String.self, forKey: .ffmpegExecutablePath)
        appearancePreference = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearancePreference) ?? .system
        allowsInsecureDownloads = try container.decodeIfPresent(Bool.self, forKey: .allowsInsecureDownloads)
            ?? container.decodeIfPresent(Bool.self, forKey: .allowsInsecureEpisodeDownloads)
            ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ffmpegExecutablePath, forKey: .ffmpegExecutablePath)
        try container.encode(appearancePreference, forKey: .appearancePreference)
        try container.encode(allowsInsecureDownloads, forKey: .allowsInsecureDownloads)
    }
}
