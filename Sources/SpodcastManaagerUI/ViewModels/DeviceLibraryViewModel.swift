import Foundation
import Observation
import SpodcastManaagerCore

@MainActor
@Observable
public final class DeviceLibraryViewModel {
    public private(set) var filesBySubscriptionID: [UUID: [URL]]
    public private(set) var lastErrorMessage: String?

    private let deviceLibrary: any DeviceLibraryInspecting

    public init(deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary()) {
        self.deviceLibrary = deviceLibrary
        self.filesBySubscriptionID = [:]
        self.lastErrorMessage = nil
    }

    public func refresh(device: DeviceInfo?, subscriptions: [FeedSubscription]) {
        guard let device else {
            filesBySubscriptionID = [:]
            lastErrorMessage = nil
            return
        }

        do {
            var updatedFiles: [UUID: [URL]] = [:]
            for subscription in subscriptions {
                let managedDirectoryURL = device.musicURL.appendingPathComponent(subscription.title, isDirectory: true)
                let files = try deviceLibrary.files(in: managedDirectoryURL)
                    .filter { $0.hasDirectoryPath == false }
                    .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                updatedFiles[subscription.id] = files
            }
            filesBySubscriptionID = updatedFiles
            lastErrorMessage = nil
        } catch {
            filesBySubscriptionID = [:]
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func files(for subscription: FeedSubscription) -> [URL] {
        filesBySubscriptionID[subscription.id] ?? []
    }
}
