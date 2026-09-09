import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct AppReleaseIdentityTests {
    @Test
    func formatsTheReleaseTagUsedInAbout() {
        #expect(AppReleaseIdentity.displayName(forReleaseTag: "v0.1.0-beta.6") == "0.1.0 beta.6")
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
