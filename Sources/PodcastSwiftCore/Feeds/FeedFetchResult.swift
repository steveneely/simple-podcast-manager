import Foundation

public struct FeedFetchResult: Equatable, Sendable {
    public var selectedEpisodes: [Episode]
    public var failures: [FeedFetchFailure]

    public init(
        selectedEpisodes: [Episode],
        failures: [FeedFetchFailure] = []
    ) {
        self.selectedEpisodes = selectedEpisodes
        self.failures = failures
    }
}

public struct FeedFetchFailure: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var subscriptionID: UUID
    public var subscriptionTitle: String
    public var message: String

    public init(
        id: UUID = UUID(),
        subscriptionID: UUID,
        subscriptionTitle: String,
        message: String
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.subscriptionTitle = subscriptionTitle
        self.message = message
    }
}
