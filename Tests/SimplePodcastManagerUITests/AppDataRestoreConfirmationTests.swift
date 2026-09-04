import Foundation
import Testing
@testable import SimplePodcastManagerUI

struct AppDataRestoreConfirmationTests {
    @Test
    func describesWhatRestoreReplacesAndPreserves() {
        let confirmation = AppDataRestoreConfirmation(
            backupURL: URL(fileURLWithPath: "/Downloads/Before Trip.spmbackup")
        )

        #expect(confirmation.title == "Restore App Data?")
        #expect(confirmation.cancelButtonTitle == "Cancel")
        #expect(confirmation.restoreButtonTitle == "Restore")
        #expect(confirmation.message.contains("Before Trip.spmbackup"))
        #expect(confirmation.message.contains("replaces your podcasts, settings, and episode history"))
        #expect(confirmation.message.contains("current app data will be backed up first"))
        #expect(confirmation.message.contains("Downloaded audio files will not be deleted"))
    }
}
