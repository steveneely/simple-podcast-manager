import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct SyncExecutionViewModelTests {
    @Test
    func dryRunSyncBuildsPreviewResultWithoutExecutingMutations() async {
        let device = DeviceInfo(
            name: "SPM Test Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/music", isDirectory: true),
            trashURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/.Trashes", isDirectory: true)
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
            manualDeleteTargets: [],
            ejectAfterSync: false,
            isDryRun: true
        )

        #expect(viewModel.lastResult?.isDryRun == true)
        #expect(viewModel.lastResult?.copiedCount == 1)
        #expect(viewModel.lastResult?.deletedCount == 0)
        #expect(executor.executeCallCount == 0)
    }

    @Test
    func syncUsesExecutorAndCapturesResult() async {
        let device = DeviceInfo(
            name: "SPM Test Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/music", isDirectory: true),
            trashURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/.Trashes", isDirectory: true)
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
        let executor = RecordingSyncExecutor(result: SyncResult(isDryRun: false, copiedCount: 1))
        let viewModel = SyncExecutionViewModel(
            planner: SyncPlanner(deviceLibrary: StubExecutionPlanDeviceLibrary(filesByDirectory: [:])),
            executor: executor
        )

        await viewModel.sync(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [subscription],
            manualDeleteTargets: [],
            ejectAfterSync: false,
            isDryRun: false
        )

        #expect(executor.executeCallCount == 1)
        #expect(executor.reportedProgress.count == 2)
        #expect(viewModel.lastResult?.copiedCount == 1)
        #expect(viewModel.progress == nil)
        #expect(viewModel.lastErrorMessage == nil)
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
    private(set) var reportedProgress: [SyncExecutionProgress] = []
    private let result: SyncResult

    init(result: SyncResult = SyncResult(isDryRun: false)) {
        self.result = result
    }

    func execute(
        plan: SyncPlan,
        progress: (@Sendable (SyncExecutionProgress) -> Void)?
    ) throws -> SyncResult {
        executeCallCount += 1
        let updates = [
            SyncExecutionProgress(
                totalCount: plan.actions.count,
                completedCount: 0,
                currentActionDescription: plan.actions.first?.summaryDescription
            ),
            SyncExecutionProgress(
                totalCount: plan.actions.count,
                completedCount: plan.actions.count
            ),
        ]
        for update in updates {
            reportedProgress.append(update)
            progress?(update)
        }
        return result
    }
}
