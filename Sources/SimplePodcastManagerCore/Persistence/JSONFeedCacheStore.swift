import Foundation

public struct JSONFeedCacheStore: FeedCacheStore {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func loadCachedFeed(for subscription: FeedSubscription) throws -> CachedFeed? {
        let fileURL = fileURL(for: subscription.id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let cachedFeed = try? Self.makeDecoder().decode(CachedFeed.self, from: Data(contentsOf: fileURL)) else {
            return nil
        }

        guard cachedFeed.subscriptionID == subscription.id, cachedFeed.rssURL == subscription.rssURL else {
            return nil
        }

        return cachedFeed
    }

    public func saveCachedFeed(_ cachedFeed: CachedFeed) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try Self.makeEncoder().encode(cachedFeed)
        try data.write(to: fileURL(for: cachedFeed.subscriptionID), options: .atomic)
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

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
