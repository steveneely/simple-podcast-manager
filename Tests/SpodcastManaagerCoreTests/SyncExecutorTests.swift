import Foundation
import Testing
@testable import SpodcastManaagerCore

struct SyncExecutorTests {
    @Test
    func executeCopiesDeletesToTrashAndCountsSkippedActions() throws {
        let device = makeDevice()
        let destinationURL = device.musicURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("Episode_2.mp3", isDirectory: false)
        let deleteTargetURL = device.musicURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let sourceURL = URL(fileURLWithPath: "/tmp/Episode_2.mp3")

        let fileSystem = RecordingFileSystem(
            existingURLs: [deleteTargetURL],
            directoryContents: [:]
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
        #expect(!ejector.didEject)
    }

    @Test
    func executeUsesUniqueTrashNameAndClearsTrashBeforeEject() throws {
        let device = makeDevice()
        let deleteTargetURL = device.musicURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let collidingTrashURL = device.trashURL.appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let suffixedTrashURL = device.trashURL.appendingPathComponent("Episode_1-1.mp3", isDirectory: false)
        let staleTrashURL = device.trashURL.appendingPathComponent("old.tmp", isDirectory: false)

        let fileSystem = RecordingFileSystem(
            existingURLs: [deleteTargetURL, collidingTrashURL, device.trashURL, staleTrashURL],
            directoryContents: [device.trashURL.standardizedFileURL.path: [collidingTrashURL, staleTrashURL]]
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
        #expect(fileSystem.removedItems.contains(collidingTrashURL))
        #expect(fileSystem.removedItems.contains(staleTrashURL))
        #expect(ejector.didEject)
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
    private let directoryContents: [String: [URL]]

    private(set) var createdDirectories: [URL] = []
    private(set) var copiedItems: [CopyRecord] = []
    private(set) var movedItems: [MoveRecord] = []
    private(set) var removedItems: [URL] = []

    init(existingURLs: [URL], directoryContents: [String: [URL]]) {
        self.existingURLs = Set(existingURLs.map(\.standardizedFileURL))
        self.directoryContents = directoryContents
    }

    func fileExists(at url: URL) -> Bool {
        existingURLs.contains(url.standardizedFileURL)
    }

    func createDirectory(at url: URL) throws {
        createdDirectories.append(url.standardizedFileURL)
        existingURLs.insert(url.standardizedFileURL)
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        copiedItems.append(.init(source: sourceURL, destination: destinationURL.standardizedFileURL))
        existingURLs.insert(destinationURL.standardizedFileURL)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        movedItems.append(.init(source: sourceURL.standardizedFileURL, destination: destinationURL.standardizedFileURL))
        existingURLs.remove(sourceURL.standardizedFileURL)
        existingURLs.insert(destinationURL.standardizedFileURL)
    }

    func removeItem(at url: URL) throws {
        removedItems.append(url.standardizedFileURL)
        existingURLs.remove(url.standardizedFileURL)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        directoryContents[url.standardizedFileURL.path] ?? []
    }
}

private final class RecordingDeviceEjector: DeviceEjecting, @unchecked Sendable {
    private(set) var didEject = false

    func eject(device: DeviceInfo) throws {
        didEject = true
    }
}
