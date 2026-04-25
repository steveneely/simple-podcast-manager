import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct GitHubUpdateCheckerTests {
    @Test
    func detectsNewerPrerelease() {
        #expect(GitHubUpdateChecker.isUpdateAvailable(
            currentReleaseTag: "v0.1.0-beta.5",
            latestReleaseTag: "v0.1.0-beta.6"
        ))
    }

    @Test
    func releaseBeatsPrerelease() {
        #expect(GitHubUpdateChecker.isUpdateAvailable(
            currentReleaseTag: "v0.1.0-beta.6",
            latestReleaseTag: "v0.1.0"
        ))
    }

    @Test
    func sameReleaseDoesNotNeedUpdate() {
        #expect(!GitHubUpdateChecker.isUpdateAvailable(
            currentReleaseTag: "v0.1.0-beta.6",
            latestReleaseTag: "v0.1.0-beta.6"
        ))
    }

    @Test
    func unknownCurrentTagDoesNotNeedUpdate() {
        #expect(!GitHubUpdateChecker.isUpdateAvailable(
            currentReleaseTag: nil,
            latestReleaseTag: "v0.1.0-beta.6"
        ))
    }
}
