import Foundation
import Testing
@testable import PodcastSwiftCore
@testable import PodcastSwiftUI

@MainActor
struct DeviceViewModelTests {
    @Test
    func autoSelectsSingleDiscoveredDevice() throws {
        let viewModel = DeviceViewModel(
            service: MockDeviceService(
                devices: [
                    DeviceInfo(
                        name: "WALKMAN",
                        rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
                        musicURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true),
                        trashURL: URL(fileURLWithPath: "/Volumes/WALKMAN/.Trashes", isDirectory: true)
                    )
                ]
            )
        )

        viewModel.refresh()

        #expect(viewModel.selectedDevice?.name == "WALKMAN")
        #expect(viewModel.hasMultipleDevices == false)
    }

    @Test
    func requiresSelectionWhenMultipleDevicesArePresent() throws {
        let viewModel = DeviceViewModel(
            service: MockDeviceService(
                devices: [
                    DeviceInfo(
                        name: "Device A",
                        rootURL: URL(fileURLWithPath: "/Volumes/A", isDirectory: true),
                        musicURL: URL(fileURLWithPath: "/Volumes/A/music", isDirectory: true),
                        trashURL: URL(fileURLWithPath: "/Volumes/A/.Trashes", isDirectory: true)
                    ),
                    DeviceInfo(
                        name: "Device B",
                        rootURL: URL(fileURLWithPath: "/Volumes/B", isDirectory: true),
                        musicURL: URL(fileURLWithPath: "/Volumes/B/music", isDirectory: true),
                        trashURL: URL(fileURLWithPath: "/Volumes/B/.Trashes", isDirectory: true)
                    ),
                ]
            )
        )

        viewModel.refresh()

        #expect(viewModel.selectedDevice == nil)
        #expect(viewModel.hasMultipleDevices == true)

        viewModel.selectDevice(id: "/Volumes/B")
        #expect(viewModel.selectedDevice?.name == "Device B")
    }

    @Test
    func noDeviceProducesBlockedState() throws {
        let viewModel = DeviceViewModel(service: MockDeviceService(devices: []))

        viewModel.refresh()

        #expect(viewModel.devices.isEmpty)
        #expect(viewModel.selectedDevice == nil)
        #expect(viewModel.statusMessage == "No compatible device detected.")
    }
}

private struct MockDeviceService: DeviceService {
    let devices: [DeviceInfo]

    func discoverDevices() throws -> [DeviceInfo] {
        devices
    }
}
