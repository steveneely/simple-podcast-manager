import Foundation

public struct SyncExecutor: Sendable, SyncExecuting {
    private let fileSystem: any FileSystemOperating
    private let storageInspector: any SyncStorageInspecting
    private let safetyValidator: SafetyValidator
    private let deletionService: DeviceFileDeletionService
    private let ejector: any DeviceEjecting
    private let playlistFileWriter: any PodcastPlaylistFileWriting

    public init(
        fileSystem: any FileSystemOperating = LocalFileSystem(),
        storageInspector: any SyncStorageInspecting = LocalSyncStorageInspector(),
        safetyValidator: SafetyValidator = SafetyValidator(),
        playlistFileWriter: any PodcastPlaylistFileWriting = LocalPodcastPlaylistFileWriter(),
        ejector: any DeviceEjecting = DiskUtilityDeviceEjector()
    ) {
        self.fileSystem = fileSystem
        self.storageInspector = storageInspector
        self.safetyValidator = safetyValidator
        self.deletionService = DeviceFileDeletionService(
            fileSystem: fileSystem,
            safetyValidator: safetyValidator
        )
        self.playlistFileWriter = playlistFileWriter
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
        let metadataCleanupTargets = plan.metadataCleanupTargets
        for target in metadataCleanupTargets {
            try safetyValidator.validateWriteTarget(target, on: plan.device)
        }
        try storageInspector.ensurePlanFits(plan.actions, on: plan.device)

        do {
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
                    try deletionService.deleteManagedFile(at: targetURL, on: plan.device) {
                        // Record the audio deletion even if later metadata cleanup fails.
                        result.deletedCount += 1
                        result.deletedBytes += fileSizeBytes
                        result.completedActions.append(action)
                    }
                    continue

                case .writePodcastPlaylist(let destinationURL, let contents, _):
                    try playlistFileWriter.write(contents, to: destinationURL)
                    try cleanPlaylistMetadataSidecar(for: destinationURL, on: plan.device)
                    result.updatedPlaylistCount += 1

                case .deletePodcastPlaylist(let targetURL):
                    try cleanPlaylistMetadataSidecar(for: targetURL, on: plan.device)
                    try playlistFileWriter.removeItemIfPresent(at: targetURL)
                    result.deletedPlaylistCount += 1

                case .ejectDevice:
                    try cleanMetadataSidecars(for: metadataCleanupTargets, on: plan.device)
                    try ejector.eject(device: plan.device)
                    result.ejected = true

                case .skip:
                    result.skippedCount += 1
                }
                result.completedActions.append(action)
            }
            if !result.ejected {
                try cleanMetadataSidecars(for: metadataCleanupTargets, on: plan.device)
            }
        } catch {
            guard !result.completedActions.isEmpty else { throw error }
            result.finishedAt = Date()
            throw SyncExecutionFailure(result: result, underlyingError: error)
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

    private func cleanMetadataSidecars(for episodeURLs: [URL], on device: DeviceInfo) throws {
        for episodeURL in episodeURLs {
            let sidecarURL = episodeURL.deletingLastPathComponent()
                .appendingPathComponent("._" + episodeURL.lastPathComponent)
            do {
                try safetyValidator.validateWriteTarget(episodeURL, on: device)
                try safetyValidator.validateDeleteTarget(sidecarURL, on: device)
                guard episodeURL.resolvingSymlinksInPath().standardizedFileURL == episodeURL.standardizedFileURL,
                      sidecarURL.resolvingSymlinksInPath().standardizedFileURL == sidecarURL.standardizedFileURL else {
                    throw CocoaError(.fileReadInvalidFileName)
                }
                guard fileSystem.fileExists(at: episodeURL) else { continue }
                guard try fileSystem.isRegularFile(at: episodeURL) else {
                    throw CocoaError(.fileReadInvalidFileName)
                }
                guard fileSystem.fileExists(at: sidecarURL) else { continue }
                guard try fileSystem.isAppleDoubleFile(at: sidecarURL) else {
                    throw SyncExecutionError.metadataCleanupFailed(
                        fileName: episodeURL.lastPathComponent,
                        detail: "The matching \(sidecarURL.lastPathComponent) is not a verified AppleDouble file and was left untouched."
                    )
                }
                try safetyValidator.validateDeleteTarget(sidecarURL, on: device)
                try fileSystem.removeItem(at: sidecarURL)
                guard !fileSystem.fileExists(at: sidecarURL) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            } catch let error as SyncExecutionError {
                throw error
            } catch {
                throw SyncExecutionError.metadataCleanupFailed(
                    fileName: episodeURL.lastPathComponent,
                    detail: error.localizedDescription
                )
            }
        }
    }

    private func cleanPlaylistMetadataSidecar(for playlistURL: URL, on device: DeviceInfo) throws {
        let sidecarURL = playlistURL.deletingLastPathComponent()
            .appendingPathComponent("._" + playlistURL.lastPathComponent)
        do {
            try safetyValidator.validatePodcastPlaylistTarget(playlistURL, on: device)
            try safetyValidator.validateDeleteTarget(sidecarURL, on: device)
            guard sidecarURL.resolvingSymlinksInPath().standardizedFileURL == sidecarURL.standardizedFileURL else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            guard fileSystem.fileExists(at: sidecarURL) else { return }
            guard try fileSystem.isRegularFile(at: sidecarURL),
                  try fileSystem.isAppleDoubleFile(at: sidecarURL) else {
                throw SyncExecutionError.metadataCleanupFailed(
                    fileName: playlistURL.lastPathComponent,
                    detail: "The matching \(sidecarURL.lastPathComponent) is not a verified AppleDouble file and was left untouched."
                )
            }
            try fileSystem.removeItem(at: sidecarURL)
            guard !fileSystem.fileExists(at: sidecarURL) else {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch let error as SyncExecutionError {
            throw error
        } catch {
            throw SyncExecutionError.metadataCleanupFailed(
                fileName: playlistURL.lastPathComponent,
                detail: error.localizedDescription
            )
        }
    }
}
