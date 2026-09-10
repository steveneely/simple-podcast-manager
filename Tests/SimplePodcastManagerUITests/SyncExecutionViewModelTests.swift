import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct SyncExecutionViewModelTests {
    @Test
    func cleanupOnlyPlanEnablesSyncWithoutAutomaticEject() {
        let root = URL(fileURLWithPath: "/Volumes/SPMTEST", isDirectory: true)
        let device = DeviceInfo(name: "SPMTEST", rootURL: root, podcastDirectoryURL: root.appendingPathComponent("music", isDirectory: true))
        let existing = device.podcastDirectoryURL.appendingPathComponent("Podcast/existing.mp3")
        #expect(SyncPlan(device: device, existingManagedEpisodeURLs: [existing]).hasWork)
        #expect(SyncPlan(device: device, actions: [.skip(reason: "Already present")], existingManagedEpisodeURLs: [existing]).hasWork)
        #expect(!SyncPlan(device: device).hasWork)
        #expect(!SyncPlan(device: device, actions: [.skip(reason: "Nothing to transfer")]).hasWork)
    }

    @Test
    func syncUsesExecutorAndCapturesResult() async {
        let device = DeviceInfo(
            name: "SPM Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/music", isDirectory: true)
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
        let executor = RecordingSyncExecutor(result: SyncResult(copiedCount: 1))
        let plan = SyncPlan(
            device: device,
            actions: [
                .copyToDevice(
                    sourceURL: preparedEpisode.preparedFileURL,
                    destinationURL: device.podcastDirectoryURL.appendingPathComponent("Example Podcast/Episode_1.mp3"),
                    fileSizeBytes: 1
                )
            ]
        )
        let viewModel = SyncExecutionViewModel(executor: executor)

        await viewModel.sync(plan: plan)

        #expect(executor.executeCallCount == 1)
        #expect(executor.reportedProgress.count == 2)
        #expect(viewModel.lastResult?.copiedCount == 1)
        #expect(viewModel.progress == nil)
        #expect(viewModel.lastErrorMessage == nil)
        #expect(viewModel.lastPlan == plan)
    }

    @Test
    func clearLastResultResetsSyncState() async {
        let device = DeviceInfo(
            name: "SPM Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/music", isDirectory: true)
        )
        let plan = SyncPlan(
            device: device,
            actions: [.skip(reason: "Already on device")]
        )
        let viewModel = SyncExecutionViewModel(executor: RecordingSyncExecutor(result: SyncResult(copiedCount: 1)))

        await viewModel.sync(plan: plan)

        viewModel.clearLastResult()

        #expect(viewModel.lastResult == nil)
        #expect(viewModel.lastErrorMessage == nil)
        #expect(viewModel.lastPlan == nil)
    }
    @Test
    func failedRetryClearsEarlierSuccessAndCapturesOnlyCurrentPartialResult() async {
        let device = DeviceInfo(name: "Test", rootURL: URL(fileURLWithPath: "/Volumes/TEST"), podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/TEST/music"))
        let plan = SyncPlan(device: device, actions: [.skip(reason: "Present")])
        let partial = SyncResult(deletedCount: 1, completedActions: [.deleteFromDevice(targetURL: device.podcastDirectoryURL.appendingPathComponent("Podcast/old.mp3"), fileSizeBytes: 1)])
        let executor = SequenceSyncExecutor(results: [
            .success(SyncResult(copiedCount: 3)),
            .failure(SyncExecutionFailure(result: partial, underlyingError: CocoaError(.fileWriteUnknown))),
            .failure(CocoaError(.fileWriteUnknown)),
            .success(SyncResult(copiedCount: 1))
        ])
        let model = SyncExecutionViewModel(executor: executor)
        await model.sync(plan: plan)
        #expect(model.lastResult?.copiedCount == 3)
        await model.sync(plan: plan)
        #expect(model.lastResult == partial)
        #expect(model.lastErrorMessage != nil)
        await model.sync(plan: plan)
        #expect(model.lastResult == nil)
        #expect(model.lastErrorMessage != nil)
        #expect(!model.isSyncing)
        await model.sync(plan: plan)
        #expect(model.lastResult?.copiedCount == 1)
        #expect(model.lastErrorMessage == nil)
        await model.sync(plan: nil)
        #expect(model.lastResult == nil)
        #expect(model.lastPlan == nil)
    }

}

private final class RecordingSyncExecutor: @unchecked Sendable, SyncExecuting {
    private(set) var executeCallCount = 0
    private(set) var reportedProgress: [SyncExecutionProgress] = []
    private let result: SyncResult

    init(result: SyncResult = SyncResult()) {
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

private final class SequenceSyncExecutor: SyncExecuting, @unchecked Sendable {
    private var results: [Result<SyncResult, any Error>]
    init(results: [Result<SyncResult, any Error>]) { self.results = results }
    func execute(plan: SyncPlan, progress: (@Sendable (SyncExecutionProgress) -> Void)?) throws -> SyncResult {
        try results.removeFirst().get()
    }
}
