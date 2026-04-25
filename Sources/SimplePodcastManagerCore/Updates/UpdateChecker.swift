import Foundation

public protocol UpdateChecking: Sendable {
    func checkForUpdates(currentReleaseTag: String?) async throws -> UpdateCheckResult
}

public struct UpdateCheckResult: Equatable, Sendable {
    public var latestRelease: AppRelease
    public var isUpdateAvailable: Bool
    public var currentReleaseTag: String?

    public init(latestRelease: AppRelease, isUpdateAvailable: Bool, currentReleaseTag: String?) {
        self.latestRelease = latestRelease
        self.isUpdateAvailable = isUpdateAvailable
        self.currentReleaseTag = currentReleaseTag
    }
}

public struct AppRelease: Equatable, Sendable, Identifiable {
    public var id: String { tagName }
    public var name: String
    public var tagName: String
    public var htmlURL: URL
    public var isPrerelease: Bool

    public init(name: String, tagName: String, htmlURL: URL, isPrerelease: Bool) {
        self.name = name
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.isPrerelease = isPrerelease
    }
}
