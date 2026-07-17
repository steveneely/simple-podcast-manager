import Testing
@testable import SimplePodcastManagerCore

struct StartupUpdateCheckPolicyTests {
    @Test
    func checksOnceAtStartupWhenAutomaticChecksAreEnabledAndReady() {
        #expect(StartupUpdateCheckPolicy.shouldCheck(
            automaticallyChecksForUpdates: true,
            canCheckForUpdates: true,
            hasCheckedThisLaunch: false
        ))
    }

    @Test(arguments: [
        (false, true, false),
        (true, false, false),
        (true, true, true),
    ])
    func skipsStartupCheckWhenDisabledUnavailableOrAlreadyChecked(
        automaticallyChecksForUpdates: Bool,
        canCheckForUpdates: Bool,
        hasCheckedThisLaunch: Bool
    ) {
        #expect(!StartupUpdateCheckPolicy.shouldCheck(
            automaticallyChecksForUpdates: automaticallyChecksForUpdates,
            canCheckForUpdates: canCheckForUpdates,
            hasCheckedThisLaunch: hasCheckedThisLaunch
        ))
    }
}
