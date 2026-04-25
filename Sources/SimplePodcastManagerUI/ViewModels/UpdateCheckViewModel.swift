import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class UpdateCheckViewModel {
    public private(set) var isChecking: Bool
    public private(set) var latestResult: UpdateCheckResult?
    public private(set) var lastErrorMessage: String?

    private let updateChecker: any UpdateChecking
    private let releaseIdentity: AppReleaseIdentity

    public init(
        updateChecker: any UpdateChecking = GitHubUpdateChecker(),
        releaseIdentity: AppReleaseIdentity = .current()
    ) {
        self.updateChecker = updateChecker
        self.releaseIdentity = releaseIdentity
        self.isChecking = false
        self.latestResult = nil
        self.lastErrorMessage = nil
    }

    public var displayVersion: String {
        releaseIdentity.displayVersion
    }

    public func checkForUpdates() async {
        isChecking = true
        defer { isChecking = false }

        do {
            latestResult = try await updateChecker.checkForUpdates(currentReleaseTag: releaseIdentity.currentReleaseTag)
            lastErrorMessage = nil
        } catch {
            latestResult = nil
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func clearResult() {
        latestResult = nil
        lastErrorMessage = nil
    }
}
