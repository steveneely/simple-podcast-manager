import Foundation
import Observation
import SPodcastManagerCore

@MainActor
@Observable
public final class DeviceViewModel {
    public private(set) var devices: [DeviceInfo]
    public private(set) var selectedDeviceID: String?
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedDevices: Bool
    public private(set) var isDisconnecting: Bool

    private let service: any DeviceService
    private let ejector: any DeviceEjecting

    public init(
        service: any DeviceService = MountedVolumeDeviceService(),
        ejector: any DeviceEjecting = DiskUtilityDeviceEjector()
    ) {
        self.service = service
        self.ejector = ejector
        self.devices = []
        self.selectedDeviceID = nil
        self.lastErrorMessage = nil
        self.hasLoadedDevices = false
        self.isDisconnecting = false
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

    public func disconnectSelectedDevice() {
        guard let selectedDevice else { return }

        isDisconnecting = true
        defer { isDisconnecting = false }

        do {
            try ejector.eject(device: selectedDevice)
            lastErrorMessage = nil
            refresh()
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
