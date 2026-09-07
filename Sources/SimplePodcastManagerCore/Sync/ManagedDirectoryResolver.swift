import Foundation

public struct ManagedDirectoryResolver: Sendable {
    public init() {}

    public func managedDirectoryURL(
        for subscription: PodcastSubscription,
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

        let matchingDirectories = candidateDirectories.filter { directoryURL in
            subscription.currentAndPreviousTitles.contains {
                EpisodeFileName.titlesMatch(directoryURL.lastPathComponent, $0)
            }
        }

        if matchingDirectories.count == 1 {
            return matchingDirectories[0]
        }

        return exactURL
    }
}
