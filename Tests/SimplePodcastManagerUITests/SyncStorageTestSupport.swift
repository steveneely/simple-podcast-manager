import Foundation
@testable import SimplePodcastManagerCore

struct TestUISyncStorageInspector: SyncStorageInspecting {
    func availableCapacity(on device: DeviceInfo) throws -> Int64 { .max }
    func fileSize(at url: URL) throws -> Int64 { 1 }
}

func makeTestPlanner(
    deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary()
) -> SyncPlanner {
    SyncPlanner(
        deviceLibrary: deviceLibrary,
        storageInspector: TestUISyncStorageInspector()
    )
}
