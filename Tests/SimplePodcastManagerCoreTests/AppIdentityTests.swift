import Testing
import Foundation
@testable import SimplePodcastManagerCore

struct AppIdentityTests {
    @Test
    func legacySupportDirectoryNamesIncludePreviousAppNames() {
        #expect(AppIdentity.legacySupportDirectoryNames.contains("SPodcastManager"))
        #expect(AppIdentity.legacySupportDirectoryNames.contains("SpodcastManaager"))
        #expect(AppIdentity.legacySupportDirectoryNames.contains("PodcastSwift"))
    }

    @Test
    func swiftRunUsesRepositoryLocalDevelopmentDataDirectory() {
        let supportURL = AppIdentity.applicationSupportDirectory(
            bundleURL: URL(fileURLWithPath: "/Users/sneely/code/simple-podcast-manager/.build/debug/Simple Podcast Manager")
        )

        #expect(supportURL.path.hasSuffix("/simple-podcast-manager/.dev-data/SimplePodcastManager"))
    }

    @Test
    func appBundleUsesUserApplicationSupportDirectory() {
        let supportURL = AppIdentity.applicationSupportDirectory(
            bundleURL: URL(fileURLWithPath: "/Applications/Simple Podcast Manager.app", isDirectory: true),
            migrateLegacyData: false
        )

        #expect(supportURL.lastPathComponent == AppIdentity.supportDirectoryName)
        #expect(!supportURL.path.contains("/.dev-data/"))
    }
}
