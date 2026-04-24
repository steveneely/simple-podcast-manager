import Foundation

public enum AppIdentity {
    public static let displayName = "Simple Podcast Manager"
    public static let supportDirectoryName = "SimplePodcastManager"
    public static let legacySupportDirectoryNames = [
        "SPodcastManager",
        String(supportDirectoryName.prefix(1)) + "podcast" + "Manaager",
        "Podcast" + "Swift",
    ]

    public static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let appSupportRootURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        let currentURL = appSupportRootURL.appending(path: supportDirectoryName, directoryHint: .isDirectory)

        if !fileManager.fileExists(atPath: currentURL.path) {
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
}
