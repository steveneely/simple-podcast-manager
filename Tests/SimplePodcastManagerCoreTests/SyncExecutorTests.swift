import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct SyncExecutorTests {
    @Test
    func executeCopiesDeletesDirectlyAndCountsSkippedActions() throws {
        let device = makeDevice()
        let managedDirectory = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
        let destinationURL = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("Episode_2.mp3", isDirectory: false)
        let deleteTargetURL = managedDirectory
            .appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let sidecarURL = managedDirectory
            .appendingPathComponent("._Episode_1.mp3", isDirectory: false)
        let sourceURL = URL(fileURLWithPath: "/tmp/Episode_2.mp3")

        let fileSystem = RecordingFileSystem(
            existingURLs: [deleteTargetURL, sidecarURL, managedDirectory],
            directoryContents: [
                managedDirectory.standardizedFileURL.path: [deleteTargetURL, sidecarURL]
            ]
        )
        let ejector = RecordingDeviceEjector()
        let executor = makeTestExecutor(fileSystem: fileSystem, ejector: ejector)

        let result = try executor.execute(
            plan: SyncPlan(
                device: device,
                actions: [
                    .copyToDevice(sourceURL: sourceURL, destinationURL: destinationURL, fileSizeBytes: 1),
                    .deleteFromDevice(targetURL: deleteTargetURL, fileSizeBytes: 1),
                    .skip(reason: "Already on device"),
                ]
            )
        )

        #expect(result.copiedCount == 1)
        #expect(result.copiedBytes == 1)
        #expect(result.deletedCount == 1)
        #expect(result.deletedBytes == 1)
        #expect(result.skippedCount == 1)
        #expect(fileSystem.createdDirectories.contains(destinationURL.deletingLastPathComponent()))
        #expect(fileSystem.copiedItems.contains(where: { $0.source == sourceURL && $0.destination == destinationURL }))
        #expect(fileSystem.removedItems.contains(deleteTargetURL.standardizedFileURL))
        #expect(fileSystem.removedItems.contains(sidecarURL.standardizedFileURL))
        #expect(!fileSystem.removedItems.contains(managedDirectory.standardizedFileURL))
        #expect(!ejector.didEject)
    }

    @Test
    func executeDeletesDirectlyBeforeEject() throws {
        let device = makeDevice()
        let managedDirectory = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
        let deleteTargetURL = managedDirectory.appendingPathComponent("Episode_1.mp3", isDirectory: false)

        let fileSystem = RecordingFileSystem(
            existingURLs: [deleteTargetURL, managedDirectory],
            directoryContents: [
                managedDirectory.standardizedFileURL.path: [deleteTargetURL],
            ]
        )
        let ejector = RecordingDeviceEjector()
        let executor = makeTestExecutor(fileSystem: fileSystem, ejector: ejector)

        let result = try executor.execute(
            plan: SyncPlan(
                device: device,
                actions: [
                    .deleteFromDevice(targetURL: deleteTargetURL, fileSizeBytes: 1),
                    .ejectDevice(deviceRootURL: device.rootURL),
                ]
            )
        )

        #expect(result.deletedCount == 1)
        #expect(result.deletedBytes == 1)
        #expect(result.ejected)
        #expect(fileSystem.removedItems.contains(deleteTargetURL.standardizedFileURL))
        #expect(fileSystem.removedItems.contains(managedDirectory.standardizedFileURL))
        #expect(ejector.didEject)
    }

    @Test
    func executeKeepsPodcastFolderWhenOtherEpisodesRemain() throws {
        let device = makeDevice()
        let managedDirectory = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
        let deleteTargetURL = managedDirectory.appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let remainingEpisodeURL = managedDirectory.appendingPathComponent("Episode_2.mp3", isDirectory: false)

        let fileSystem = RecordingFileSystem(
            existingURLs: [deleteTargetURL, remainingEpisodeURL, managedDirectory],
            directoryContents: [
                managedDirectory.standardizedFileURL.path: [deleteTargetURL, remainingEpisodeURL]
            ]
        )
        let executor = makeTestExecutor(fileSystem: fileSystem, ejector: RecordingDeviceEjector())

        _ = try executor.execute(
            plan: SyncPlan(
                device: device,
                actions: [
                    .deleteFromDevice(targetURL: deleteTargetURL, fileSizeBytes: 1)
                ]
            )
        )

        #expect(!fileSystem.removedItems.contains(managedDirectory.standardizedFileURL))
    }

    @Test
    func executeReportsProgressAcrossPlannedActions() throws {
        let device = makeDevice()
        let destinationURL = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("Episode_2.mp3", isDirectory: false)
        let sourceURL = URL(fileURLWithPath: "/tmp/Episode_2.mp3")

        let deleteTargetURL = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("Episode_1.mp3", isDirectory: false)

        let fileSystem = RecordingFileSystem(
            existingURLs: [deleteTargetURL],
            directoryContents: [:]
        )
        let executor = makeTestExecutor(fileSystem: fileSystem, ejector: RecordingDeviceEjector())
        let collector = SyncProgressCollector()

        _ = try executor.execute(
            plan: SyncPlan(
                device: device,
                actions: [
                    .copyToDevice(sourceURL: sourceURL, destinationURL: destinationURL, fileSizeBytes: 1),
                    .deleteFromDevice(targetURL: deleteTargetURL, fileSizeBytes: 1),
                    .skip(reason: "Already on device"),
                ]
            ),
            progress: { collector.append($0) }
        )

        let updates = collector.values
        #expect(updates.count == 4)
        #expect(updates[0] == SyncExecutionProgress(totalCount: 3, completedCount: 0, currentActionDescription: "Copy to device: Example Podcast / Episode_2.mp3"))
        #expect(updates[1] == SyncExecutionProgress(totalCount: 3, completedCount: 1, currentActionDescription: "Delete old episode: Example Podcast / Episode_1.mp3"))
        #expect(updates[2] == SyncExecutionProgress(totalCount: 3, completedCount: 2, currentActionDescription: "Skip: Already on device"))
        #expect(updates[3] == SyncExecutionProgress(totalCount: 3, completedCount: 3))
    }

    @Test
    func rechecksPlanCapacityImmediatelyBeforeExecution() throws {
        let device = makeDevice()
        let sourceURL = URL(fileURLWithPath: "/tmp/Episode_2.mp3")
        let destinationURL = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast/Episode_2.mp3")
        let fileSystem = RecordingFileSystem(existingURLs: [], directoryContents: [:])
        let executor = makeTestExecutor(
            fileSystem: fileSystem,
            storageInspector: TestSyncStorageInspector(
                availableBytes: 50,
                sizesByPath: [sourceURL.path: 100]
            ),
            ejector: RecordingDeviceEjector()
        )

        #expect(throws: SyncCapacityError.insufficientCapacity(requiredBytes: 100, availableBytes: 50)) {
            try executor.execute(plan: SyncPlan(
                device: device,
                actions: [.copyToDevice(sourceURL: sourceURL, destinationURL: destinationURL, fileSizeBytes: 100)]
            ))
        }
        #expect(fileSystem.copiedItems.isEmpty)
    }

    @Test
    func reportsWhenCopyFailureMayHaveLeftPartialFile() throws {
        let device = makeDevice()
        let sourceURL = URL(fileURLWithPath: "/tmp/Episode_2.mp3")
        let destinationURL = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast/Episode_2.mp3")
        let fileSystem = RecordingFileSystem(
            existingURLs: [],
            directoryContents: [:],
            failCopiesLeavingPartialFile: true
        )
        let executor = makeTestExecutor(
            fileSystem: fileSystem,
            ejector: RecordingDeviceEjector()
        )

        do {
            _ = try executor.execute(plan: SyncPlan(
                device: device,
                actions: [.copyToDevice(sourceURL: sourceURL, destinationURL: destinationURL, fileSizeBytes: 1)]
            ))
            Issue.record("Expected the copy to fail")
        } catch let error as SyncExecutionError {
            guard case .copyFailed(let fileName, let partialFileMayRemain, _) = error else {
                Issue.record("Expected copyFailed, got \(error)")
                return
            }
            #expect(fileName == sourceURL.lastPathComponent)
            #expect(partialFileMayRemain)
        }
    }

    private func makeDevice() -> DeviceInfo {
        DeviceInfo(
            name: "SPM Test Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/music", isDirectory: true)
        )
    }
}

private final class RecordingFileSystem: FileSystemOperating, @unchecked Sendable {
    struct CopyRecord: Equatable {
        let source: URL
        let destination: URL
    }

    private var existingURLs: Set<URL>
    private var directoryContents: [String: Set<URL>]
    private let failCopiesLeavingPartialFile: Bool

    private(set) var createdDirectories: [URL] = []
    private(set) var copiedItems: [CopyRecord] = []
    private(set) var removedItems: [URL] = []

    init(
        existingURLs: [URL],
        directoryContents: [String: [URL]],
        failCopiesLeavingPartialFile: Bool = false
    ) {
        self.existingURLs = Set(existingURLs.map(\.standardizedFileURL))
        self.directoryContents = directoryContents.reduce(into: [:]) { result, entry in
            result[entry.key] = Set(entry.value.map(\.standardizedFileURL))
        }
        self.failCopiesLeavingPartialFile = failCopiesLeavingPartialFile
    }

    func fileExists(at url: URL) -> Bool {
        existingURLs.contains(url.standardizedFileURL)
    }

    func createDirectory(at url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        createdDirectories.append(standardizedURL)
        existingURLs.insert(standardizedURL)
        directoryContents[standardizedURL.path] = directoryContents[standardizedURL.path] ?? []
        addChild(standardizedURL, to: standardizedURL.deletingLastPathComponent())
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        let standardizedDestination = destinationURL.standardizedFileURL
        if failCopiesLeavingPartialFile {
            existingURLs.insert(standardizedDestination)
            addChild(standardizedDestination, to: standardizedDestination.deletingLastPathComponent())
            throw TestCopyError.failed
        }
        copiedItems.append(.init(source: sourceURL, destination: standardizedDestination))
        existingURLs.insert(standardizedDestination)
        addChild(standardizedDestination, to: standardizedDestination.deletingLastPathComponent())
    }

    func removeItem(at url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        removedItems.append(standardizedURL)
        existingURLs.remove(standardizedURL)
        removeChild(standardizedURL, from: standardizedURL.deletingLastPathComponent())
        directoryContents.removeValue(forKey: standardizedURL.path)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        return Array(directoryContents[url.standardizedFileURL.path] ?? []).sorted {
            $0.path < $1.path
        }
    }

    private func addChild(_ childURL: URL, to parentURL: URL) {
        let parentPath = parentURL.standardizedFileURL.path
        directoryContents[parentPath, default: []].insert(childURL.standardizedFileURL)
    }

    private func removeChild(_ childURL: URL, from parentURL: URL) {
        let parentPath = parentURL.standardizedFileURL.path
        directoryContents[parentPath]?.remove(childURL.standardizedFileURL)
    }
}

private enum TestCopyError: Error {
    case failed
}

private final class RecordingDeviceEjector: DeviceEjecting, @unchecked Sendable {
    private(set) var didEject = false

    func eject(device: DeviceInfo) throws {
        didEject = true
    }
}

private final class SyncProgressCollector: @unchecked Sendable {
    private var updates: [SyncExecutionProgress] = []

    func append(_ progress: SyncExecutionProgress) {
        updates.append(progress)
    }

    var values: [SyncExecutionProgress] {
        updates
    }
}
