import Foundation
import Testing
@testable import SPodcastManagerCore

struct SyncExecutorTests {
    @Test
    func executeCopiesDeletesToTrashAndCountsSkippedActions() throws {
        let device = makeDevice()
        let managedDirectory = device.musicURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
        let destinationURL = device.musicURL
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
        let executor = SyncExecutor(fileSystem: fileSystem, ejector: ejector)

        let result = try executor.execute(
            plan: SyncPlan(
                device: device,
                isDryRun: false,
                actions: [
                    .copyToDevice(sourceURL: sourceURL, destinationURL: destinationURL),
                    .deleteFromDevice(targetURL: deleteTargetURL),
                    .skip(reason: "Already on device"),
                ]
            )
        )

        #expect(result.copiedCount == 1)
        #expect(result.deletedCount == 1)
        #expect(result.skippedCount == 1)
        #expect(fileSystem.createdDirectories.contains(destinationURL.deletingLastPathComponent()))
        #expect(fileSystem.copiedItems.contains(where: { $0.source == sourceURL && $0.destination == destinationURL }))
        #expect(fileSystem.movedItems.contains(where: { $0.source == deleteTargetURL && $0.destination == device.trashURL.appendingPathComponent("Episode_1.mp3") }))
        #expect(fileSystem.movedItems.contains(where: { $0.source == sidecarURL && $0.destination == device.trashURL.appendingPathComponent("._Episode_1.mp3") }))
        #expect(!fileSystem.removedItems.contains(managedDirectory.standardizedFileURL))
        #expect(!ejector.didEject)
    }

    @Test
    func executeUsesUniqueTrashNameAndClearsTrashBeforeEject() throws {
        let device = makeDevice()
        let managedDirectory = device.musicURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
        let deleteTargetURL = device.musicURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let collidingTrashURL = device.trashURL.appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let suffixedTrashURL = device.trashURL.appendingPathComponent("Episode_1-1.mp3", isDirectory: false)
        let staleTrashURL = device.trashURL.appendingPathComponent("old.tmp", isDirectory: false)

        let fileSystem = RecordingFileSystem(
            existingURLs: [deleteTargetURL, collidingTrashURL, device.trashURL, staleTrashURL, managedDirectory],
            directoryContents: [
                managedDirectory.standardizedFileURL.path: [deleteTargetURL],
                device.trashURL.standardizedFileURL.path: [collidingTrashURL, staleTrashURL]
            ]
        )
        let ejector = RecordingDeviceEjector()
        let executor = SyncExecutor(fileSystem: fileSystem, ejector: ejector)

        let result = try executor.execute(
            plan: SyncPlan(
                device: device,
                isDryRun: false,
                actions: [
                    .deleteFromDevice(targetURL: deleteTargetURL),
                    .clearDeviceTrash(trashURL: device.trashURL),
                    .ejectDevice(deviceRootURL: device.rootURL),
                ]
            )
        )

        #expect(result.deletedCount == 1)
        #expect(result.ejected)
        #expect(fileSystem.movedItems.contains(where: { $0.source == deleteTargetURL && $0.destination == suffixedTrashURL }))
        #expect(fileSystem.removedItems.contains(managedDirectory.standardizedFileURL))
        #expect(fileSystem.removedItems.contains(collidingTrashURL))
        #expect(fileSystem.removedItems.contains(staleTrashURL))
        #expect(ejector.didEject)
    }

    @Test
    func executeKeepsPodcastFolderWhenOtherEpisodesRemain() throws {
        let device = makeDevice()
        let managedDirectory = device.musicURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
        let deleteTargetURL = managedDirectory.appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let remainingEpisodeURL = managedDirectory.appendingPathComponent("Episode_2.mp3", isDirectory: false)

        let fileSystem = RecordingFileSystem(
            existingURLs: [deleteTargetURL, remainingEpisodeURL, managedDirectory],
            directoryContents: [
                managedDirectory.standardizedFileURL.path: [deleteTargetURL, remainingEpisodeURL]
            ]
        )
        let executor = SyncExecutor(fileSystem: fileSystem, ejector: RecordingDeviceEjector())

        _ = try executor.execute(
            plan: SyncPlan(
                device: device,
                isDryRun: false,
                actions: [
                    .deleteFromDevice(targetURL: deleteTargetURL)
                ]
            )
        )

        #expect(!fileSystem.removedItems.contains(managedDirectory.standardizedFileURL))
    }

    @Test
    func executeReportsProgressAcrossPlannedActions() throws {
        let device = makeDevice()
        let destinationURL = device.musicURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("Episode_2.mp3", isDirectory: false)
        let sourceURL = URL(fileURLWithPath: "/tmp/Episode_2.mp3")

        let fileSystem = RecordingFileSystem(
            existingURLs: [device.trashURL],
            directoryContents: [:]
        )
        let executor = SyncExecutor(fileSystem: fileSystem, ejector: RecordingDeviceEjector())
        let collector = SyncProgressCollector()

        _ = try executor.execute(
            plan: SyncPlan(
                device: device,
                isDryRun: false,
                actions: [
                    .copyToDevice(sourceURL: sourceURL, destinationURL: destinationURL),
                    .clearDeviceTrash(trashURL: device.trashURL),
                    .skip(reason: "Already on device"),
                ]
            ),
            progress: { collector.append($0) }
        )

        let updates = collector.values
        #expect(updates.count == 4)
        #expect(updates[0] == SyncExecutionProgress(totalCount: 3, completedCount: 0, currentActionDescription: "Copy to device: Example Podcast / Episode_2.mp3"))
        #expect(updates[1] == SyncExecutionProgress(totalCount: 3, completedCount: 1, currentActionDescription: "Clear device trash"))
        #expect(updates[2] == SyncExecutionProgress(totalCount: 3, completedCount: 2, currentActionDescription: "Skip: Already on device"))
        #expect(updates[3] == SyncExecutionProgress(totalCount: 3, completedCount: 3))
    }

    private func makeDevice() -> DeviceInfo {
        DeviceInfo(
            name: "WALKMAN",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true),
            trashURL: URL(fileURLWithPath: "/Volumes/WALKMAN/.Trashes", isDirectory: true)
        )
    }
}

private final class RecordingFileSystem: FileSystemOperating, @unchecked Sendable {
    struct CopyRecord: Equatable {
        let source: URL
        let destination: URL
    }

    struct MoveRecord: Equatable {
        let source: URL
        let destination: URL
    }

    private var existingURLs: Set<URL>
    private var directoryContents: [String: Set<URL>]

    private(set) var createdDirectories: [URL] = []
    private(set) var copiedItems: [CopyRecord] = []
    private(set) var movedItems: [MoveRecord] = []
    private(set) var removedItems: [URL] = []

    init(existingURLs: [URL], directoryContents: [String: [URL]]) {
        self.existingURLs = Set(existingURLs.map(\.standardizedFileURL))
        self.directoryContents = directoryContents.reduce(into: [:]) { result, entry in
            result[entry.key] = Set(entry.value.map(\.standardizedFileURL))
        }
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
        copiedItems.append(.init(source: sourceURL, destination: standardizedDestination))
        existingURLs.insert(standardizedDestination)
        addChild(standardizedDestination, to: standardizedDestination.deletingLastPathComponent())
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        let standardizedSource = sourceURL.standardizedFileURL
        let standardizedDestination = destinationURL.standardizedFileURL
        movedItems.append(.init(source: standardizedSource, destination: standardizedDestination))
        existingURLs.remove(standardizedSource)
        existingURLs.insert(standardizedDestination)
        removeChild(standardizedSource, from: standardizedSource.deletingLastPathComponent())
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
        Array(directoryContents[url.standardizedFileURL.path] ?? []).sorted {
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
