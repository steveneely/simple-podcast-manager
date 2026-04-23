import Foundation

public struct SyncExecutor: Sendable, SyncExecuting {
    private let fileSystem: any FileSystemOperating
    private let safetyValidator: SafetyValidator
    private let ejector: any DeviceEjecting

    public init(
        fileSystem: any FileSystemOperating = LocalFileSystem(),
        safetyValidator: SafetyValidator = SafetyValidator(),
        ejector: any DeviceEjecting = DiskUtilityDeviceEjector()
    ) {
        self.fileSystem = fileSystem
        self.safetyValidator = safetyValidator
        self.ejector = ejector
    }

    public func execute(
        plan: SyncPlan,
        progress: (@Sendable (SyncExecutionProgress) -> Void)? = nil
    ) throws -> SyncResult {
        var result = SyncResult(startedAt: Date(), isDryRun: false)
        let totalCount = plan.actions.count

        try safetyValidator.validateDevice(plan.device)

        for (index, action) in plan.actions.enumerated() {
            progress?(
                SyncExecutionProgress(
                    totalCount: totalCount,
                    completedCount: index,
                    currentActionDescription: action.summaryDescription
                )
            )
            try safetyValidator.validate(action, on: plan.device)

            switch action {
            case .copyToDevice(let sourceURL, let destinationURL):
                guard let parentDirectoryURL = destinationURL.deletingLastPathComponent() as URL? else {
                    throw SyncExecutionError.missingParentDirectory(destinationURL)
                }
                try fileSystem.createDirectory(at: parentDirectoryURL)
                if fileSystem.fileExists(at: destinationURL) {
                    try fileSystem.removeItem(at: destinationURL)
                }
                try fileSystem.copyItem(at: sourceURL, to: destinationURL)
                result.copiedCount += 1

            case .deleteFromDevice(let targetURL):
                let trashDestinationURL = uniqueTrashDestination(for: targetURL, in: plan.device.trashURL)
                try fileSystem.createDirectory(at: plan.device.trashURL)
                if fileSystem.fileExists(at: trashDestinationURL) {
                    try fileSystem.removeItem(at: trashDestinationURL)
                }
                try fileSystem.moveItem(at: targetURL, to: trashDestinationURL)
                try moveAppleDoubleSidecarIfPresent(for: targetURL, to: plan.device.trashURL)
                try removeEmptyManagedDirectoryIfNeeded(containing: targetURL, on: plan.device)
                result.deletedCount += 1

            case .clearDeviceTrash(let trashURL):
                guard fileSystem.fileExists(at: trashURL) else { continue }
                for childURL in try fileSystem.contentsOfDirectory(at: trashURL) {
                    try fileSystem.removeItem(at: childURL)
                }

            case .ejectDevice:
                try ejector.eject(device: plan.device)
                result.ejected = true

            case .skip:
                result.skippedCount += 1
            }
        }

        result.finishedAt = Date()
        progress?(
            SyncExecutionProgress(
                totalCount: totalCount,
                completedCount: totalCount
            )
        )
        return result
    }

    private func uniqueTrashDestination(for targetURL: URL, in trashURL: URL) -> URL {
        let baseName = targetURL.deletingPathExtension().lastPathComponent
        let pathExtension = targetURL.pathExtension
        var candidateURL = trashURL.appendingPathComponent(targetURL.lastPathComponent, isDirectory: false)
        var suffix = 1

        while fileSystem.fileExists(at: candidateURL) {
            let candidateName = pathExtension.isEmpty
                ? "\(baseName)-\(suffix)"
                : "\(baseName)-\(suffix).\(pathExtension)"
            candidateURL = trashURL.appendingPathComponent(candidateName, isDirectory: false)
            suffix += 1
        }

        return candidateURL
    }

    private func moveAppleDoubleSidecarIfPresent(for targetURL: URL, to trashURL: URL) throws {
        let sidecarURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent("._" + targetURL.lastPathComponent, isDirectory: false)
        guard fileSystem.fileExists(at: sidecarURL) else { return }

        let trashDestinationURL = uniqueTrashDestination(for: sidecarURL, in: trashURL)
        if fileSystem.fileExists(at: trashDestinationURL) {
            try fileSystem.removeItem(at: trashDestinationURL)
        }
        try fileSystem.moveItem(at: sidecarURL, to: trashDestinationURL)
    }

    private func removeEmptyManagedDirectoryIfNeeded(containing targetURL: URL, on device: DeviceInfo) throws {
        let managedDirectoryURL = targetURL.deletingLastPathComponent().standardizedFileURL
        guard managedDirectoryURL.deletingLastPathComponent().standardizedFileURL == device.musicURL.standardizedFileURL else {
            return
        }
        guard fileSystem.fileExists(at: managedDirectoryURL) else {
            return
        }

        let remainingChildren = try fileSystem.contentsOfDirectory(at: managedDirectoryURL)
        guard remainingChildren.isEmpty else {
            return
        }

        try safetyValidator.validateDeleteTarget(managedDirectoryURL, on: device)
        try fileSystem.removeItem(at: managedDirectoryURL)
    }
}
