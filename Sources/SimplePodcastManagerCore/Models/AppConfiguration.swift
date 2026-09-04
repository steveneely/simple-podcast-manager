import Foundation

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var settings: AppSettings
    public var podcastSubscriptions: [PodcastSubscription]

    public init(
        settings: AppSettings = AppSettings(),
        podcastSubscriptions: [PodcastSubscription] = []
    ) {
        self.settings = settings
        self.podcastSubscriptions = podcastSubscriptions
    }

    private enum CodingKeys: String, CodingKey {
        case settings
        // Keep the established JSON key so existing app data remains readable.
        case podcastSubscriptions = "feedSubscriptions"
    }
}
