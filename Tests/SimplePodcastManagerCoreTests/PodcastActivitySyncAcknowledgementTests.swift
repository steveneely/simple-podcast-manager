import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct PodcastActivitySyncAcknowledgementTests {
    @Test
    func acknowledgesExactCopiesAndRetainedExistingFilesButNotDeletedOrUnplannedEpisodes() {
        let root = URL(fileURLWithPath: "/Volumes/SPMTEST")
        let device = DeviceInfo(
            name: "SPMTEST",
            rootURL: root,
            podcastDirectoryURL: root.appending(path: "music", directoryHint: .isDirectory)
        )
        let copied = prepared("copied")
        let retained = prepared("retained")
        let deleted = prepared("deleted")
        let unplanned = prepared("unplanned")
        let retainedURL = root.appending(path: "music/Show/retained.mp3")
        let deletedURL = root.appending(path: "music/Show/deleted.mp3")
        let plan = SyncPlan(device: device, actions: [
            .copyToDevice(sourceURL: copied.preparedFileURL, destinationURL: root.appending(path: "music/Show/copied.mp3"), fileSizeBytes: 1),
            .deleteFromDevice(targetURL: deletedURL, fileSizeBytes: 1),
        ])
        let existing = [
            PodcastActivityEpisodeKey(episode: retained.episode)!: retainedURL,
            PodcastActivityEpisodeKey(episode: deleted.episode)!: deletedURL,
        ]

        let acknowledged = PodcastActivitySyncAcknowledgement.episodesAcknowledged(
            preparedEpisodes: [copied, retained, deleted, unplanned],
            existingDeviceFiles: existing,
            completedPlan: plan
        )

        #expect(Set(acknowledged.map(\.id)) == ["copied", "retained"])
    }

    private func prepared(_ id: String) -> PreparedEpisode {
        let subscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let episode = Episode(
            id: id,
            subscriptionID: subscriptionID,
            podcastTitle: "Show",
            title: id,
            enclosureURL: URL(string: "https://example.com/\(id).mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        return PreparedEpisode(
            episode: episode,
            sourceFileURL: URL(fileURLWithPath: "/tmp/\(id)-source.mp3"),
            preparedFileURL: URL(fileURLWithPath: "/tmp/\(id)-prepared.mp3"),
            preparationAction: .passthroughMP3
        )
    }
}
