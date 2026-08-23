import Testing
@testable import SimplePodcastManagerUI

struct SyncPresentationTests {
    @Test
    func cleanupNoticeNamesTheConfiguredThreshold() {
        let notice = SyncPresentation.deletionNotice(
            deletionCount: 2,
            selectedCleanupDeletionCount: 2,
            cleanupEpisodeAgeDays: 30
        )

        #expect(SyncPresentation.deletionNoticeTitle(selectedCleanupDeletionCount: 2) == "Old Episodes Selected for Cleanup")
        #expect(notice.contains("2 episodes older than 30 days"))
        #expect(notice.contains("Device Cleanup is configured in Settings"))
    }

    @Test
    func manualRemovalNoticeDoesNotDescribeDeviceDeletion() {
        let notice = SyncPresentation.deletionNotice(
            deletionCount: 1,
            selectedCleanupDeletionCount: 0,
            cleanupEpisodeAgeDays: nil
        )

        #expect(SyncPresentation.deletionNoticeTitle(selectedCleanupDeletionCount: 0) == "Episodes Selected for Removal")
        #expect(notice == "1 episode is selected for removal during this sync. Review the planned actions before syncing.")
    }
}
