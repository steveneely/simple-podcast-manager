import Testing
@testable import SimplePodcastManagerCore

struct AppIdentityTests {
    @Test
    func legacySupportDirectoryNamesIncludePreviousAppNames() {
        #expect(AppIdentity.legacySupportDirectoryNames.contains("SPodcastManager"))
        #expect(AppIdentity.legacySupportDirectoryNames.contains("SpodcastManaager"))
        #expect(AppIdentity.legacySupportDirectoryNames.contains("PodcastSwift"))
    }
}
