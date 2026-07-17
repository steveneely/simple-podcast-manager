import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct AppReleaseIdentityTests {
    @Test
    func displayReleaseUsesReleaseTagWhenAvailable() {
        let identity = AppReleaseIdentity(
            currentReleaseTag: "v0.1.0-beta.6",
            displayVersion: "0.1.0 (1)"
        )

        #expect(identity.displayRelease == "0.1.0 beta.6")
        #expect(identity.isDevelopmentBuild == false)
    }

    @Test
    func displayReleaseFallsBackToLocalBuildVersion() {
        let identity = AppReleaseIdentity(
            currentReleaseTag: nil,
            displayVersion: "0.1.0 (1)"
        )

        #expect(identity.displayRelease == "local build 0.1.0 (1)")
        #expect(identity.isDevelopmentBuild == true)
    }

    @Test
    func validatesNumericBundleVersionsForSparkle() {
        #expect(AppReleaseIdentity.isValidBundleVersion("26"))
        #expect(AppReleaseIdentity.isValidBundleVersion("1024"))
        #expect(!AppReleaseIdentity.isValidBundleVersion(""))
        #expect(!AppReleaseIdentity.isValidBundleVersion("0.1.0-beta.26"))
        #expect(!AppReleaseIdentity.isValidBundleVersion("build-26"))
    }

    @Test
    func packagedAppDisallowsSilentAutomaticUpdates() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = repositoryRoot.appendingPathComponent("Packaging/Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        #expect(plist["SUAllowsAutomaticUpdates"] as? Bool == false)
    }
}
