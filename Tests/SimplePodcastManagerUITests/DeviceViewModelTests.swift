import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct DeviceViewModelTests {
    @Test
    func autoSelectsSingleDiscoveredDevice() async throws {
        let viewModel = DeviceViewModel(
            service: MockDeviceService(
                devices: [
                    DeviceInfo(
                        name: "WALKMAN",
                        rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
                        podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
                    )
                ]
            )
        )

        await viewModel.refresh()

        #expect(viewModel.selectedDevice?.name == "WALKMAN")
        #expect(viewModel.hasMultipleDevices == false)
    }

    @Test
    func requiresSelectionWhenMultipleDevicesArePresent() async throws {
        let viewModel = DeviceViewModel(
            service: MockDeviceService(
                devices: [
                    DeviceInfo(
                        name: "Device A",
                        rootURL: URL(fileURLWithPath: "/Volumes/A", isDirectory: true),
                        podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/A/music", isDirectory: true)
                    ),
                    DeviceInfo(
                        name: "Device B",
                        rootURL: URL(fileURLWithPath: "/Volumes/B", isDirectory: true),
                        podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/B/music", isDirectory: true)
                    ),
                ]
            )
        )

        await viewModel.refresh()

        #expect(viewModel.selectedDevice == nil)
        #expect(viewModel.hasMultipleDevices == true)

        viewModel.selectDevice(id: "/Volumes/B")
        #expect(viewModel.selectedDevice?.name == "Device B")
    }

    @Test
    func noDeviceProducesBlockedState() async throws {
        let viewModel = DeviceViewModel(service: MockDeviceService(devices: []))

        await viewModel.refresh()

        #expect(viewModel.devices.isEmpty)
        #expect(viewModel.selectedDevice == nil)
        #expect(viewModel.statusMessage == "No compatible device detected.")
    }

    @Test
    func replacesSelectedDeviceDetailsWithoutWaitingForRediscovery() async throws {
        let initialDevice = DeviceInfo(
            name: "WALKMAN",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let updatedDevice = DeviceInfo(
            name: "WALKMAN",
            rootURL: initialDevice.rootURL,
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/Podcast", isDirectory: true)
        )
        let viewModel = DeviceViewModel(service: MockDeviceService(devices: [initialDevice]))
        await viewModel.refresh()

        viewModel.replaceDevice(updatedDevice)

        #expect(viewModel.selectedDevice == updatedDevice)
    }

    @Test
    func disconnectSelectedDeviceEjectsAndRefreshesDevices() async throws {
        let initialDevice = DeviceInfo(
            name: "WALKMAN",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let service = RefreshingMockDeviceService(deviceLists: [[initialDevice], []])
        let ejector = RecordingDeviceEjector()
        let viewModel = DeviceViewModel(service: service, ejector: ejector)

        await viewModel.refresh()
        await viewModel.disconnectSelectedDevice()

        #expect(ejector.ejectedDevices == [initialDevice])
        #expect(viewModel.selectedDevice == nil)
        #expect(viewModel.devices.isEmpty)
    }

    @Test
    func disconnectSelectedDeviceSurfacesEjectError() async throws {
        let initialDevice = DeviceInfo(
            name: "WALKMAN",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let viewModel = DeviceViewModel(
            service: MockDeviceService(devices: [initialDevice]),
            ejector: FailingDeviceEjector()
        )

        await viewModel.refresh()
        await viewModel.disconnectSelectedDevice()

        #expect(viewModel.selectedDevice?.name == "WALKMAN")
        #expect(viewModel.lastErrorMessage == "Could not eject the device at /Volumes/WALKMAN.")
    }

    @Test
    func refreshClearsSelectionWhenPreviouslySelectedDeviceIsRemovedExternally() async throws {
        let deviceA = DeviceInfo(
            name: "Device A",
            rootURL: URL(fileURLWithPath: "/Volumes/A", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/A/music", isDirectory: true)
        )
        let deviceB = DeviceInfo(
            name: "Device B",
            rootURL: URL(fileURLWithPath: "/Volumes/B", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/B/music", isDirectory: true)
        )
        let service = RefreshingMockDeviceService(deviceLists: [[deviceA, deviceB], [deviceA]])
        let viewModel = DeviceViewModel(service: service)

        await viewModel.refresh()
        viewModel.selectDevice(id: deviceB.id)

        await viewModel.refresh()

        #expect(viewModel.devices == [deviceA])
        #expect(viewModel.selectedDevice?.id == deviceA.id)
        #expect(viewModel.hasMultipleDevices == false)
    }

    @Test
    func refreshDiscoversDevicesOutsideMainThread() async {
        let service = ThreadRecordingDeviceService()
        let viewModel = DeviceViewModel(service: service)

        await viewModel.refresh()

        #expect(service.discoveryMainThreadValues == [false])
    }
}

private struct MockDeviceService: DeviceService {
    let devices: [DeviceInfo]

    func discoverDevices() throws -> [DeviceInfo] {
        devices
    }
}

private final class RefreshingMockDeviceService: DeviceService, @unchecked Sendable {
    private var deviceLists: [[DeviceInfo]]
    private var index = 0

    init(deviceLists: [[DeviceInfo]]) {
        self.deviceLists = deviceLists
    }

    func discoverDevices() throws -> [DeviceInfo] {
        let currentIndex = min(index, max(deviceLists.count - 1, 0))
        let result = deviceLists[currentIndex]
        index += 1
        return result
    }
}

private final class RecordingDeviceEjector: DeviceEjecting, @unchecked Sendable {
    private(set) var ejectedDevices: [DeviceInfo] = []

    func eject(device: DeviceInfo) throws {
        ejectedDevices.append(device)
    }
}

private struct FailingDeviceEjector: DeviceEjecting {
    func eject(device: DeviceInfo) throws {
        throw SyncExecutionError.ejectFailed(device.rootURL.path)
    }
}

private final class ThreadRecordingDeviceService: DeviceService, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    var discoveryMainThreadValues: [Bool] {
        lock.withLock { values }
    }

    func discoverDevices() throws -> [DeviceInfo] {
        lock.withLock { values.append(Thread.isMainThread) }
        return []
    }
}
