import Testing
import Foundation
@testable import SimplePodcastManagerCore

struct AppIdentityTests {
    @Test
    func swiftRunUsesRepositoryLocalDevelopmentDataDirectory() {
        let supportURL = AppIdentity.applicationSupportDirectory(
            bundleURL: URL(fileURLWithPath: "/Users/sneely/code/simple-podcast-manager/.build/debug/Simple Podcast Manager")
        )
        let repositoryRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        let expectedURL = repositoryRootURL
            .appending(path: AppIdentity.developmentDataDirectoryName, directoryHint: .isDirectory)
            .appending(path: AppIdentity.supportDirectoryName, directoryHint: .isDirectory)

        #expect(supportURL == expectedURL)
    }

    @Test
    func appBundleUsesUserApplicationSupportDirectory() {
        let supportURL = AppIdentity.applicationSupportDirectory(
            bundleURL: URL(fileURLWithPath: "/Applications/Simple Podcast Manager.app", isDirectory: true)
        )

        #expect(supportURL.lastPathComponent == AppIdentity.supportDirectoryName)
        #expect(!supportURL.path.contains("/.dev-data/"))
    }
}
