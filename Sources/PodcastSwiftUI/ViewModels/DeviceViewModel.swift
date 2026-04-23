import Foundation
import Observation
import PodcastSwiftCore

@MainActor
@Observable
public final class DeviceViewModel {
    public private(set) var devices: [DeviceInfo]
    public private(set) var selectedDeviceID: String?
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedDevices: Bool

    private let service: any DeviceService

    public init(service: any DeviceService = MountedVolumeDeviceService()) {
        self.service = service
        self.devices = []
        self.selectedDeviceID = nil
        self.lastErrorMessage = nil
        self.hasLoadedDevices = false
    }

    public var selectedDevice: DeviceInfo? {
        guard let selectedDeviceID else { return nil }
        return devices.first(where: { $0.id == selectedDeviceID })
    }

    public var hasMultipleDevices: Bool {
        devices.count > 1
    }

    public var statusMessage: String {
        if let selectedDevice {
            return "Ready: \(selectedDevice.name)"
        }

        if devices.isEmpty {
            return "No compatible device detected."
        }

        return "Multiple compatible devices found. Choose one to continue."
    }

    public func refresh() {
        do {
            let discoveredDevices = try service.discoverDevices()
            self.devices = discoveredDevices
            self.lastErrorMessage = nil
            self.hasLoadedDevices = true
            updateSelection(afterRefreshingWith: discoveredDevices)
        } catch {
            self.devices = []
            self.selectedDeviceID = nil
            self.lastErrorMessage = error.localizedDescription
            self.hasLoadedDevices = true
        }
    }

    public func selectDevice(id: String) {
        guard devices.contains(where: { $0.id == id }) else { return }
        selectedDeviceID = devices.first(where: { $0.id == id })?.id
    }

    private func updateSelection(afterRefreshingWith discoveredDevices: [DeviceInfo]) {
        if let selectedDeviceID,
           discoveredDevices.contains(where: { $0.id == selectedDeviceID }) {
            self.selectedDeviceID = selectedDeviceID
            return
        }

        if discoveredDevices.count == 1 {
            self.selectedDeviceID = discoveredDevices[0].id
        } else {
            self.selectedDeviceID = nil
        }
    }
}
