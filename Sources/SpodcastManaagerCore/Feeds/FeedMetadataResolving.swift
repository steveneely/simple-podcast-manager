import Foundation

public protocol FeedMetadataResolving: Sendable {
    func resolveMetadata(for rssURL: URL, subscriptionID: UUID?) async throws -> FeedSummary
}
