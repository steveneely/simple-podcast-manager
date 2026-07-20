import Foundation

/// Performs validated device deletions and removes metadata files created by macOS.
public struct DeviceFileDeletionService: Sendable {
    private let fileSystem: any FileSystemOperating
    private let safetyValidator: SafetyValidator

    public init(
        fileSystem: any FileSystemOperating = LocalFileSystem(),
        safetyValidator: SafetyValidator = SafetyValidator()
    ) {
        self.fileSystem = fileSystem
        self.safetyValidator = safetyValidator
    }

    public func deleteExplicitFile(at targetURL: URL, on device: DeviceInfo) throws {
        try deleteValidatedFile(at: targetURL, on: device)

        let sidecarURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent("._" + targetURL.lastPathComponent, isDirectory: false)
        if fileSystem.fileExists(at: sidecarURL) {
            try deleteValidatedFile(at: sidecarURL, on: device)
        }
    }

    public func deleteManagedFile(at targetURL: URL, on device: DeviceInfo) throws {
        try deleteExplicitFile(at: targetURL, on: device)
        try removeEmptyManagedDirectory(containing: targetURL, on: device)
    }

    private func deleteValidatedFile(at targetURL: URL, on device: DeviceInfo) throws {
        try safetyValidator.validateDeleteTarget(targetURL, on: device)
        try fileSystem.removeItem(at: targetURL)
    }

    private func removeEmptyManagedDirectory(containing targetURL: URL, on device: DeviceInfo) throws {
        let managedDirectoryURL = targetURL.deletingLastPathComponent().standardizedFileURL
        guard managedDirectoryURL.deletingLastPathComponent().standardizedFileURL == device.podcastDirectoryURL.standardizedFileURL else {
            return
        }
        guard fileSystem.fileExists(at: managedDirectoryURL) else { return }
        guard try fileSystem.contentsOfDirectory(at: managedDirectoryURL).isEmpty else { return }

        try deleteValidatedFile(at: managedDirectoryURL, on: device)
    }
}
