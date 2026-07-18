import Foundation
@testable import SimplePodcastManagerCore

struct TestSyncStorageInspector: SyncStorageInspecting {
    var availableBytes: Int64 = .max
    var sizesByPath: [String: Int64] = [:]
    var defaultFileSize: Int64 = 1

    func availableCapacity(on device: DeviceInfo) throws -> Int64 {
        availableBytes
    }

    func fileSize(at url: URL) throws -> Int64 {
        sizesByPath[url.standardizedFileURL.path] ?? defaultFileSize
    }
}

func makeTestPlanner(
    deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary(),
    storageInspector: any SyncStorageInspecting = TestSyncStorageInspector()
) -> SyncPlanner {
    SyncPlanner(deviceLibrary: deviceLibrary, storageInspector: storageInspector)
}

func makeTestExecutor(
    fileSystem: any FileSystemOperating = LocalFileSystem(),
    storageInspector: any SyncStorageInspecting = TestSyncStorageInspector(),
    ejector: any DeviceEjecting = DiskUtilityDeviceEjector()
) -> SyncExecutor {
    SyncExecutor(
        fileSystem: fileSystem,
        storageInspector: storageInspector,
        ejector: ejector
    )
}
