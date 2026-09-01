import Foundation
import Observation
import SimplePodcastManagerCore

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
    private var latestRefreshID: UUID?

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

    public func refresh() async {
        let refreshID = UUID()
        latestRefreshID = refreshID
        do {
            let service = self.service
            let discoveredDevices = try await Task.detached(priority: .userInitiated) {
                try service.discoverDevices()
            }.value
            guard latestRefreshID == refreshID else { return }
            self.devices = discoveredDevices
            self.lastErrorMessage = nil
            self.hasLoadedDevices = true
            updateSelection(afterRefreshingWith: discoveredDevices)
        } catch {
            guard latestRefreshID == refreshID else { return }
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

    public func replaceDevice(_ updatedDevice: DeviceInfo) {
        guard let index = devices.firstIndex(where: { $0.id == updatedDevice.id }) else { return }
        devices[index] = updatedDevice
        if selectedDeviceID == updatedDevice.id {
            selectedDeviceID = updatedDevice.id
        }
    }

    public func disconnectSelectedDevice() async {
        guard let selectedDevice else { return }

        isDisconnecting = true
        defer { isDisconnecting = false }

        do {
            let ejector = self.ejector
            try await Task.detached(priority: .userInitiated) {
                try ejector.eject(device: selectedDevice)
            }.value
            lastErrorMessage = nil
            await refresh()
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
