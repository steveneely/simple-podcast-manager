public enum StartupUpdateCheckPolicy {
    public static func shouldCheck(
        automaticallyChecksForUpdates: Bool,
        canCheckForUpdates: Bool,
        hasCheckedThisLaunch: Bool
    ) -> Bool {
        automaticallyChecksForUpdates && canCheckForUpdates && !hasCheckedThisLaunch
    }
}
