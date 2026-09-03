import Foundation
@testable import SimplePodcastManagerCore

struct TestUISyncStorageInspector: SyncStorageInspecting {
    var availableBytes: Int64 = .max
    var fileSizeBytes: Int64 = 1
    var sizesByPath: [String: Int64] = [:]

    func availableCapacity(on device: DeviceInfo) throws -> Int64 { availableBytes }
    func fileSize(at url: URL) throws -> Int64 {
        sizesByPath[url.standardizedFileURL.path] ?? fileSizeBytes
    }
}

func makeTestPlanner(
    deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary(),
    storageInspector: any SyncStorageInspecting = TestUISyncStorageInspector()
) -> SyncPlanner {
    SyncPlanner(
        deviceLibrary: deviceLibrary,
        storageInspector: storageInspector
    )
}
