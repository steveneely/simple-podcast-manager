import Foundation

public struct JSONFeedCacheStore: FeedCacheStore {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func loadCachedFeed(for subscription: PodcastSubscription) throws -> CachedFeed? {
        let fileURL = fileURL(for: subscription.id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard var cachedFeed = try? AppJSONFile.decode(CachedFeed.self, from: fileURL) else {
            return nil
        }

        guard
            cachedFeed.subscriptionID == subscription.id,
            cachedFeed.rssURL == subscription.rssURL
        else {
            return nil
        }

        cachedFeed.episodes = cachedFeed.episodes.map(PublicationDateNormalizer.normalize)
        return cachedFeed
    }

    public func saveCachedFeed(_ cachedFeed: CachedFeed) throws {
        try AppJSONFile.save(cachedFeed, to: fileURL(for: cachedFeed.subscriptionID))
    }

    public func deleteCachedFeed(for subscriptionID: UUID) throws {
        let fileURL = fileURL(for: subscriptionID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    public static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "feed-cache", directoryHint: .isDirectory)
    }

    private func fileURL(for subscriptionID: UUID) -> URL {
        directoryURL.appending(path: "\(subscriptionID.uuidString).json", directoryHint: .notDirectory)
    }
}
