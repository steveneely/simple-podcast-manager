import Foundation

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var settings: AppSettings
    public var feedSubscriptions: [FeedSubscription]

    public init(
        settings: AppSettings = AppSettings(),
        feedSubscriptions: [FeedSubscription] = []
    ) {
        self.settings = settings
        self.feedSubscriptions = feedSubscriptions
    }
}
