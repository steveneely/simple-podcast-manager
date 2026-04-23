import Foundation

public struct SyncPlanner: Sendable {
    private let deviceLibrary: any DeviceLibraryInspecting
    private let safetyValidator: SafetyValidator

    public init(
        deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary(),
        safetyValidator: SafetyValidator = SafetyValidator()
    ) {
        self.deviceLibrary = deviceLibrary
        self.safetyValidator = safetyValidator
    }

    public func makePlan(
        device: DeviceInfo,
        preparedEpisodes: [PreparedEpisode],
        subscriptions: [FeedSubscription],
        manualDeleteTargets: Set<URL> = [],
        ejectAfterSync: Bool,
        isDryRun: Bool
    ) throws -> SyncPlan {
        try safetyValidator.validateDevice(device)

        var actions: [SyncAction] = []
        var plannedDeletionTargets: Set<URL> = []

        let preparedBySubscription = Dictionary(grouping: preparedEpisodes.compactMap { preparedEpisode -> (UUID, PreparedEpisode)? in
            guard let subscriptionID = preparedEpisode.episode.subscriptionID else { return nil }
            return (subscriptionID, preparedEpisode)
        }, by: { $0.0 })
        let manualDeleteTargets = Set(manualDeleteTargets.map(\.standardizedFileURL))

        for subscription in subscriptions {
            let preparedEpisodes = preparedBySubscription[subscription.id]?.map(\.1) ?? []
            let managedDirectory = managedDirectoryURL(for: subscription, on: device)
            let existingFiles = try deviceLibrary.files(in: managedDirectory)
            let existingFileNames = Set(existingFiles.map(\.lastPathComponent))

            for preparedEpisode in preparedEpisodes {
                let destinationURL = managedDirectory.appendingPathComponent(preparedEpisode.preparedFileURL.lastPathComponent, isDirectory: false)

                if existingFileNames.contains(destinationURL.lastPathComponent) {
                    actions.append(.skip(reason: "Already on device: \(preparedEpisode.episode.title)"))
                } else {
                    try safetyValidator.validateWriteTarget(destinationURL, on: device)
                    actions.append(.copyToDevice(sourceURL: preparedEpisode.preparedFileURL, destinationURL: destinationURL))
                }
            }

            let manuallySelectedFiles = existingFiles
                .filter { manualDeleteTargets.contains($0.standardizedFileURL) }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            for fileURL in manuallySelectedFiles where !plannedDeletionTargets.contains(fileURL.standardizedFileURL) {
                try safetyValidator.validateDeleteTarget(fileURL, on: device)
                actions.append(.deleteFromDevice(targetURL: fileURL))
                plannedDeletionTargets.insert(fileURL.standardizedFileURL)
            }

            let retainedFileNames = Set(preparedEpisodes.map { $0.preparedFileURL.lastPathComponent })
            let retentionLimit = subscription.retentionPolicy.episodeLimit
            if existingFiles.count + preparedEpisodes.count > retentionLimit {
                let deletableFiles = existingFiles
                    .filter { retainedFileNames.contains($0.lastPathComponent) == false }
                    .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

                let deleteCount = max(existingFiles.count + preparedEpisodes.count - retentionLimit, 0)
                for fileURL in deletableFiles.prefix(deleteCount) {
                    guard !plannedDeletionTargets.contains(fileURL.standardizedFileURL) else { continue }
                    try safetyValidator.validateDeleteTarget(fileURL, on: device)
                    actions.append(.deleteFromDevice(targetURL: fileURL))
                    plannedDeletionTargets.insert(fileURL.standardizedFileURL)
                }
            }
        }

        try safetyValidator.validateClearTrashTarget(device.trashURL, on: device)
        actions.append(.clearDeviceTrash(trashURL: device.trashURL))

        if ejectAfterSync {
            actions.append(.ejectDevice(deviceRootURL: device.rootURL))
        }

        return SyncPlan(device: device, isDryRun: isDryRun, actions: actions)
    }

    private func managedDirectoryURL(for subscription: FeedSubscription, on device: DeviceInfo) -> URL {
        return device.musicURL.appendingPathComponent(subscription.title, isDirectory: true)
    }
}
