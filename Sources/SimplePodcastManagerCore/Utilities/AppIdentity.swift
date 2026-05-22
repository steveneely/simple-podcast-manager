import Foundation

public enum AppIdentity {
    public static let displayName = "Simple Podcast Manager"
    public static let supportDirectoryName = "SimplePodcastManager"
    public static let developmentDataDirectoryName = ".dev-data"
    public static let legacySupportDirectoryNames = [
        "SPodcastManager",
        String(supportDirectoryName.prefix(1)) + "podcast" + "Manaager",
        "Podcast" + "Swift",
    ]
    private static let sourceFilePath = #filePath

    public static func applicationSupportDirectory(
        fileManager: FileManager = .default,
        bundleURL: URL = Bundle.main.bundleURL,
        migrateLegacyData: Bool = true
    ) -> URL {
        if isApplicationBundle(bundleURL) {
            return installedApplicationSupportDirectory(fileManager: fileManager, migrateLegacyData: migrateLegacyData)
        }

        return developmentSupportDirectory(fileManager: fileManager)
    }

    public static func developmentSupportDirectory(fileManager: FileManager = .default) -> URL {
        repositoryRootURL(fileManager: fileManager)
            .appending(path: developmentDataDirectoryName, directoryHint: .isDirectory)
            .appending(path: supportDirectoryName, directoryHint: .isDirectory)
    }

    private static func installedApplicationSupportDirectory(fileManager: FileManager, migrateLegacyData: Bool) -> URL {
        let appSupportRootURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        let currentURL = appSupportRootURL.appending(path: supportDirectoryName, directoryHint: .isDirectory)

        if migrateLegacyData && !fileManager.fileExists(atPath: currentURL.path) {
            for legacySupportDirectoryName in legacySupportDirectoryNames {
                let legacyURL = appSupportRootURL.appending(path: legacySupportDirectoryName, directoryHint: .isDirectory)
                if fileManager.fileExists(atPath: legacyURL.path) {
                    try? fileManager.moveItem(at: legacyURL, to: currentURL)
                    break
                }
            }
        }

        return currentURL
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
