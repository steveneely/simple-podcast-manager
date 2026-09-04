import Testing
@testable import SimplePodcastManagerUI

struct SyncPresentationTests {
    @Test
    func cleanupNoticeNamesTheConfiguredPerPodcastLimit() {
        let notice = SyncPresentation.deletionNotice(
            deletionCount: 2,
            selectedCleanupDeletionCount: 2,
            cleanupMaximumEpisodesPerPodcast: 5
        )

        #expect(SyncPresentation.deletionNoticeTitle(selectedCleanupDeletionCount: 2) == "Episodes Selected for Cleanup")
        #expect(notice.contains("keep the latest 5 episodes per podcast"))
        #expect(notice.contains("2 older episodes are selected for cleanup"))
    }

    @Test
    func manualRemovalNoticeDoesNotDescribeDeviceDeletion() {
        let notice = SyncPresentation.deletionNotice(
            deletionCount: 1,
            selectedCleanupDeletionCount: 0,
            cleanupMaximumEpisodesPerPodcast: nil
        )

        #expect(SyncPresentation.deletionNoticeTitle(selectedCleanupDeletionCount: 0) == "Episodes Selected for Removal")
        #expect(notice == "1 episode is selected for removal during this sync. Review the planned actions before syncing.")
    }
}
