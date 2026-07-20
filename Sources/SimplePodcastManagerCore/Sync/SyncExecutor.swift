import Foundation

public struct SyncExecutor: Sendable, SyncExecuting {
    private let fileSystem: any FileSystemOperating
    private let storageInspector: any SyncStorageInspecting
    private let safetyValidator: SafetyValidator
    private let deletionService: DeviceFileDeletionService
    private let ejector: any DeviceEjecting

    public init(
        fileSystem: any FileSystemOperating = LocalFileSystem(),
        storageInspector: any SyncStorageInspecting = LocalSyncStorageInspector(),
        safetyValidator: SafetyValidator = SafetyValidator(),
        ejector: any DeviceEjecting = DiskUtilityDeviceEjector()
    ) {
        self.fileSystem = fileSystem
        self.storageInspector = storageInspector
        self.safetyValidator = safetyValidator
        self.deletionService = DeviceFileDeletionService(
            fileSystem: fileSystem,
            safetyValidator: safetyValidator
        )
        self.ejector = ejector
    }

    public func execute(
        plan: SyncPlan,
        progress: (@Sendable (SyncExecutionProgress) -> Void)? = nil
    ) throws -> SyncResult {
        var result = SyncResult(startedAt: Date())
        let totalCount = plan.actions.count

        try safetyValidator.validateDevice(plan.device)
        for action in plan.actions {
            try safetyValidator.validate(action, on: plan.device)
        }
        try storageInspector.ensurePlanFits(plan.actions, on: plan.device)

        for (index, action) in plan.actions.enumerated() {
            progress?(
                SyncExecutionProgress(
                    totalCount: totalCount,
                    completedCount: index,
                    currentActionDescription: action.summaryDescription
                )
            )
            switch action {
            case .copyToDevice(let sourceURL, let destinationURL, let fileSizeBytes):
                let parentDirectoryURL = destinationURL.deletingLastPathComponent()
                try fileSystem.createDirectory(at: parentDirectoryURL)
                if fileSystem.fileExists(at: destinationURL) {
                    throw SyncExecutionError.destinationAlreadyExists(destinationURL)
                }
                do {
                    try fileSystem.copyItem(at: sourceURL, to: destinationURL)
                } catch {
                    throw SyncExecutionError.copyFailed(
                        fileName: sourceURL.lastPathComponent,
                        partialFileMayRemain: fileSystem.fileExists(at: destinationURL),
                        detail: error.localizedDescription
                    )
                }
                result.copiedCount += 1
                result.copiedBytes += fileSizeBytes

            case .deleteFromDevice(let targetURL, let fileSizeBytes):
                try deletionService.deleteManagedFile(at: targetURL, on: plan.device)
                result.deletedCount += 1
                result.deletedBytes += fileSizeBytes

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
}
