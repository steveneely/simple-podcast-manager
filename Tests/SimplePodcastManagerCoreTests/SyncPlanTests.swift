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
        ])

        #expect(plan.removalTargetURLs == [removedURL.standardizedFileURL])
    }
}
