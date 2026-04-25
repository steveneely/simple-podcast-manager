import Foundation

public struct AppReleaseIdentity: Equatable, Sendable {
    public var currentReleaseTag: String?
    public var displayVersion: String

    public init(currentReleaseTag: String?, displayVersion: String) {
        self.currentReleaseTag = currentReleaseTag
        self.displayVersion = displayVersion
    }

    public static func current(bundle: Bundle = .main) -> AppReleaseIdentity {
        let releaseTag = bundle.object(forInfoDictionaryKey: "SPMReleaseTag") as? String
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        let displayVersion: String
        switch (shortVersion, buildVersion) {
        case (.some(let shortVersion), .some(let buildVersion)):
            displayVersion = "\(shortVersion) (\(buildVersion))"
        case (.some(let shortVersion), .none):
            displayVersion = shortVersion
        default:
            displayVersion = "Local build"
        }

        return AppReleaseIdentity(currentReleaseTag: releaseTag, displayVersion: displayVersion)
    }
}
