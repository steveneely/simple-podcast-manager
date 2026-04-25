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
    }

    @Test
    func displayReleaseFallsBackToLocalBuildVersion() {
        let identity = AppReleaseIdentity(
            currentReleaseTag: nil,
            displayVersion: "0.1.0 (1)"
        )

        #expect(identity.displayRelease == "local build 0.1.0 (1)")
    }
}
