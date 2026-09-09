import Foundation

public enum AppReleaseIdentity {
    public static func displayName(forReleaseTag releaseTag: String) -> String {
        releaseTag
            .trimmingPrefix("v")
            .replacingOccurrences(of: "-", with: " ")
    }
}
