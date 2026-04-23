import Foundation
import Testing
@testable import SpodcastManaagerCore
@testable import SpodcastManaagerUI

@MainActor
struct SyncExecutionViewModelTests {
    @Test
    func dryRunSyncBuildsPreviewResultWithoutExecutingMutations() async {
        let device = DeviceInfo(
            name: "WALKMAN",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true),
            trashURL: URL(fileURLWithPath: "/Volumes/WALKMAN/.Trashes", isDirectory: true)
        )
        let preparedEpisode = PreparedEpisode(
            episode: Episode(
                id: "ep-1",
                subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                podcastTitle: "Example Podcast",
                title: "Episode 1",
                enclosureURL: URL(string: "https://cdn.example.com/ep1.mp3")!,
                sourceFeedURL: URL(string: "https://example.com/feed.xml")!
            ),
            sourceFileURL: URL(fileURLWithPath: "/tmp/Episode_1.mp3"),
            preparedFileURL: URL(fileURLWithPath: "/tmp/Episode_1.mp3"),
            preparationAction: .passthroughMP3
        )
        let subscription = FeedSubscription(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Example Podcast",
            rssURL: URL(string: "https://example.com/feed.xml")!,
            retentionPolicy: .keepLatestEpisodes(3)
        )
        let executor = RecordingSyncExecutor()
        let viewModel = SyncExecutionViewModel(
            planner: SyncPlanner(deviceLibrary: StubExecutionPlanDeviceLibrary(filesByDirectory: [:])),
            executor: executor
        )

        await viewModel.sync(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [subscription],
            ejectAfterSync: false,
            isDryRun: true
        )

        #expect(viewModel.lastResult?.isDryRun == true)
        #expect(viewModel.lastResult?.copiedCount == 1)
        #expect(viewModel.lastResult?.deletedCount == 0)
        #expect(executor.executeCallCount == 0)
    }
}

private struct StubExecutionPlanDeviceLibrary: DeviceLibraryInspecting {
    let filesByDirectory: [String: [URL]]

    func files(in directoryURL: URL) throws -> [URL] {
        filesByDirectory[directoryURL.standardizedFileURL.path] ?? []
    }
}

private final class RecordingSyncExecutor: @unchecked Sendable, SyncExecuting {
    private(set) var executeCallCount = 0

    func execute(plan: SyncPlan) throws -> SyncResult {
        executeCallCount += 1
        return SyncResult(isDryRun: false)
    }
}
