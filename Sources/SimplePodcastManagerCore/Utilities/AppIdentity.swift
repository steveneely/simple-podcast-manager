import Foundation

public enum AppIdentity {
    public static let displayName = "Simple Podcast Manager"
    public static let supportDirectoryName = "SimplePodcastManager"
    public static let developmentDataDirectoryName = ".dev-data"
    private static let sourceFilePath = #filePath

    public static func applicationSupportDirectory(
        fileManager: FileManager = .default,
        bundleURL: URL = Bundle.main.bundleURL
    ) -> URL {
        if isApplicationBundle(bundleURL) {
            return installedApplicationSupportDirectory(fileManager: fileManager)
        }

        return developmentSupportDirectory(fileManager: fileManager)
    }

    public static func developmentSupportDirectory(fileManager: FileManager = .default) -> URL {
        repositoryRootURL(fileManager: fileManager)
            .appending(path: developmentDataDirectoryName, directoryHint: .isDirectory)
            .appending(path: supportDirectoryName, directoryHint: .isDirectory)
    }

    private static func installedApplicationSupportDirectory(fileManager: FileManager) -> URL {
        let appSupportRootURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        return appSupportRootURL.appending(path: supportDirectoryName, directoryHint: .isDirectory)
    }

    private static func isApplicationBundle(_ bundleURL: URL) -> Bool {
        bundleURL.pathExtension == "app"
    }

    private static func repositoryRootURL(fileManager: FileManager) -> URL {
        let sourceURL = URL(fileURLWithPath: sourceFilePath)
        if let repositoryURL = firstAncestorContainingPackageManifest(startingAt: sourceURL.deletingLastPathComponent(), fileManager: fileManager) {
            return repositoryURL
        }

        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        if let repositoryURL = firstAncestorContainingPackageManifest(startingAt: currentDirectoryURL, fileManager: fileManager) {
            return repositoryURL
        }

        return currentDirectoryURL
    }

    private static func firstAncestorContainingPackageManifest(startingAt startURL: URL, fileManager: FileManager) -> URL? {
        var candidateURL = startURL.standardizedFileURL

        while true {
            let manifestURL = candidateURL.appending(path: "Package.swift", directoryHint: .notDirectory)
            if fileManager.fileExists(atPath: manifestURL.path) {
                return candidateURL
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            if parentURL.path == candidateURL.path {
                return nil
            }
            candidateURL = parentURL
        }
    }
}
