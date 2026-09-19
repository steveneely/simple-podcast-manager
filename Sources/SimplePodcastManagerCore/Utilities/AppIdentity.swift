import Foundation

public enum AppIdentity {
    public static let displayName = "Simple Podcast Manager"
    public static let supportDirectoryName = "SimplePodcastManager"
    public static let developmentDataDirectoryName = ".dev-data"
    private static let sourceFilePath = #filePath

    /// Only explicitly marked distribution bundles outside a checkout may use live data.
    /// Missing metadata defaults to development, including ad-hoc packaged test apps.
    public static func isDevelopmentBuild(
        fileManager: FileManager = .default,
        bundleURL: URL = Bundle.main.bundleURL,
        isDistributionBuild: Bool = Bundle.main.object(forInfoDictionaryKey: "SPMDistributionBuild") as? Bool ?? false,
        isMarkedDevelopment: Bool = Bundle.main.object(forInfoDictionaryKey: "SPMDevelopmentBuild") as? Bool ?? false
    ) -> Bool {
        isMarkedDevelopment
            || !isDistributionBuild
            || bundleURL.pathExtension != "app"
            || checkoutRoot(containing: bundleURL, fileManager: fileManager) != nil
    }

    public static func applicationSupportDirectory(
        fileManager: FileManager = .default,
        bundleURL: URL = Bundle.main.bundleURL,
        isDistributionBuild: Bool = Bundle.main.object(forInfoDictionaryKey: "SPMDistributionBuild") as? Bool ?? false,
        isMarkedDevelopment: Bool = Bundle.main.object(forInfoDictionaryKey: "SPMDevelopmentBuild") as? Bool ?? false
    ) -> URL {
        if isDevelopmentBuild(
            fileManager: fileManager,
            bundleURL: bundleURL,
            isDistributionBuild: isDistributionBuild,
            isMarkedDevelopment: isMarkedDevelopment
        ) {
            return developmentSupportDirectory(fileManager: fileManager, bundleURL: bundleURL)
        }
        return installedApplicationSupportDirectory(fileManager: fileManager)
    }

    public static func developmentSupportDirectory(
        fileManager: FileManager = .default,
        bundleURL: URL = Bundle.main.bundleURL
    ) -> URL {
        let rootURL = checkoutRoot(containing: bundleURL, fileManager: fileManager)
            ?? repositoryRootURL(fileManager: fileManager)
        return rootURL
            .appending(path: developmentDataDirectoryName, directoryHint: .isDirectory)
            .appending(path: supportDirectoryName, directoryHint: .isDirectory)
    }

    private static func checkoutRoot(containing bundleURL: URL, fileManager: FileManager) -> URL? {
        firstAncestorContainingPackageManifest(
            startingAt: bundleURL.deletingLastPathComponent().resolvingSymlinksInPath(),
            fileManager: fileManager
        )
    }

    private static func installedApplicationSupportDirectory(fileManager: FileManager) -> URL {
        let appSupportRootURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        return appSupportRootURL.appending(path: supportDirectoryName, directoryHint: .isDirectory)
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
                return candidateURL.resolvingSymlinksInPath()
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            if parentURL.path == candidateURL.path {
                return nil
            }
            candidateURL = parentURL
        }
    }
}
