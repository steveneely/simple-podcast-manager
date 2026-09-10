import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct SyncPlanTests {
    @Test
    func removalTargetsExcludeFilesCopiedBackByTheSamePlan() {
        let rootURL = URL(fileURLWithPath: "/Volumes/SPMTEST", isDirectory: true)
        let device = DeviceInfo(
            name: "SPMTEST",
            rootURL: rootURL,
            podcastDirectoryURL: rootURL.appending(path: "music", directoryHint: .isDirectory)
        )
        let replacedURL = rootURL.appending(path: "music/Show/Replaced.mp3")
        let removedURL = rootURL.appending(path: "music/Show/Removed.mp3")
        let sourceURL = URL(fileURLWithPath: "/tmp/Replaced.mp3")
        let plan = SyncPlan(device: device, actions: [
            .deleteFromDevice(targetURL: replacedURL, fileSizeBytes: 25),
            .deleteFromDevice(targetURL: removedURL, fileSizeBytes: 100),
            .copyToDevice(sourceURL: sourceURL, destinationURL: replacedURL, fileSizeBytes: 100),
        ], existingManagedEpisodeURLs: [replacedURL, removedURL])

        #expect(plan.metadataCleanupTargets == [replacedURL.standardizedFileURL])
        #expect(plan.removalTargetURLs == [removedURL.standardizedFileURL])
    }

    @Test
    func reportsOnlyPlaylistFilesWrittenByThePlan() {
        let rootURL = URL(fileURLWithPath: "/Volumes/SPMTEST", isDirectory: true)
        let device = DeviceInfo(
            name: "SPMTEST",
            rootURL: rootURL,
            podcastDirectoryURL: rootURL.appending(path: "music", directoryHint: .isDirectory)
        )
        let commuteURL = device.podcastDirectoryURL.appendingPathComponent("Commute.m3u")
        let emptyURL = device.podcastDirectoryURL.appendingPathComponent("Empty.m3u")
        let plan = SyncPlan(device: device, actions: [
            .writePodcastPlaylist(destinationURL: commuteURL, contents: Data(), episodeCount: 1),
            .deleteEmptyPodcastPlaylist(targetURL: emptyURL),
        ])

        #expect(plan.writtenPodcastPlaylistFileNames == ["Commute.m3u"])
    }

    @Test
    func describesEmptyPlaylistRemovalClearly() {
        let targetURL = URL(fileURLWithPath: "/Volumes/SPMTEST/music/News.m3u")

        #expect(
            SyncAction.deleteEmptyPodcastPlaylist(targetURL: targetURL).summaryDescription
                == "Remove empty playlist: News"
        )
    }
}
