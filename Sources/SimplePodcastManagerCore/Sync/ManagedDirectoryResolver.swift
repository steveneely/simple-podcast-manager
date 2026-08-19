import Foundation

public struct ManagedDirectoryResolver: Sendable {
    public init() {}

    public func managedDirectoryURL(
        for subscription: FeedSubscription,
        on device: DeviceInfo,
        candidateDirectories: [URL]
    ) -> URL {
        let exactURL = device.podcastDirectoryURL.appendingPathComponent(
            EpisodeFileName.directoryName(for: subscription),
            isDirectory: true
        )
        if candidateDirectories.contains(where: { $0.standardizedFileURL == exactURL.standardizedFileURL }) {
            return exactURL
        }

        let matchingDirectories = candidateDirectories.filter {
            EpisodeFileName.titlesMatch($0.lastPathComponent, subscription.title)
        }

        if matchingDirectories.count == 1 {
            return matchingDirectories[0]
        }

        return exactURL
    }
}
