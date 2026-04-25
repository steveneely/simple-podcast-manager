import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct UpdateCheckViewModelTests {
    @Test
    func checkForUpdatesCapturesAvailableRelease() async {
        let latestRelease = AppRelease(
            name: "Simple Podcast Manager v0.1.0 beta 6",
            tagName: "v0.1.0-beta.6",
            htmlURL: URL(string: "https://example.com/releases/v0.1.0-beta.6")!,
            isPrerelease: true
        )
        let viewModel = UpdateCheckViewModel(
            updateChecker: StubUpdateChecker(result: UpdateCheckResult(
                latestRelease: latestRelease,
                isUpdateAvailable: true,
                currentReleaseTag: "v0.1.0-beta.5"
            )),
            releaseIdentity: AppReleaseIdentity(currentReleaseTag: "v0.1.0-beta.5", displayVersion: "0.1.0 beta 5")
        )

        await viewModel.checkForUpdates()

        #expect(viewModel.latestResult?.latestRelease == latestRelease)
        #expect(viewModel.latestResult?.isUpdateAvailable == true)
        #expect(viewModel.lastErrorMessage == nil)
        #expect(viewModel.isChecking == false)
    }

    @Test
    func checkForUpdatesCapturesError() async {
        let viewModel = UpdateCheckViewModel(
            updateChecker: StubUpdateChecker(error: UpdateCheckError.noReleasesFound),
            releaseIdentity: AppReleaseIdentity(currentReleaseTag: "v0.1.0-beta.5", displayVersion: "0.1.0 beta 5")
        )

        await viewModel.checkForUpdates()

        #expect(viewModel.latestResult == nil)
        #expect(viewModel.lastErrorMessage == "No app releases were found.")
        #expect(viewModel.isChecking == false)
    }
}

private struct StubUpdateChecker: UpdateChecking {
    var result: UpdateCheckResult?
    var error: Error?

    init(result: UpdateCheckResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func checkForUpdates(currentReleaseTag: String?) async throws -> UpdateCheckResult {
        if let error {
            throw error
        }
        return result!
    }
}
