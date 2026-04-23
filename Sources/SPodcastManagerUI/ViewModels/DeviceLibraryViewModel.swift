import Foundation
import Observation
import SPodcastManagerCore

@MainActor
@Observable
public final class DeviceLibraryViewModel {
    public private(set) var filesBySubscriptionID: [UUID: [URL]]
    public private(set) var lastErrorMessage: String?

    private let deviceLibrary: any DeviceLibraryInspecting
    private let managedDirectoryResolver: ManagedDirectoryResolver

    public init(deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary()) {
        self.deviceLibrary = deviceLibrary
        self.managedDirectoryResolver = ManagedDirectoryResolver(deviceLibrary: deviceLibrary)
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
                let managedDirectoryURL = try managedDirectoryResolver.managedDirectoryURL(for: subscription, on: device)
                let files = try deviceLibrary.files(in: managedDirectoryURL)
                    .filter { $0.hasDirectoryPath == false && !EpisodeFileName.isMetadataSidecar($0) }
                updatedFiles[subscription.id] = sortFiles(files)
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

    private func sortFiles(_ files: [URL]) -> [URL] {
        files.sorted { lhs, rhs in
            switch (EpisodeFileName.publicationDate(from: lhs), EpisodeFileName.publicationDate(from: rhs)) {
            case let (lhsDate?, rhsDate?):
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }
}
