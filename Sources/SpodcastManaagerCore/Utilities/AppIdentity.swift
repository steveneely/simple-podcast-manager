import Foundation

public enum AppIdentity {
    public static let displayName = "Spodcast Manaager"
    public static let supportDirectoryName = "SpodcastManaager"
    public static let legacySupportDirectoryName = "PodcastSwift"

    public static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let appSupportRootURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        let currentURL = appSupportRootURL.appending(path: supportDirectoryName, directoryHint: .isDirectory)
        let legacyURL = appSupportRootURL.appending(path: legacySupportDirectoryName, directoryHint: .isDirectory)

        if !fileManager.fileExists(atPath: currentURL.path), fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.moveItem(at: legacyURL, to: currentURL)
        }

        return currentURL
    }
}
