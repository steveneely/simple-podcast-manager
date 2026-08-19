import Foundation
import Testing
@testable import SimplePodcastManagerUI

struct AppDataRestoreSuccessTests {
    @Test
    func showsSuccessfulRestoreAndPreviousBackupLocation() {
        let backupURL = URL(
            fileURLWithPath: "/Users/example/Library/Application Support/SimplePodcastManager/ImportBackups/BeforeImport-20260819-202434"
        )
        let success = AppDataRestoreSuccess(previousBackupURL: backupURL)

        #expect(success.title == "Restore Complete")
        #expect(success.doneButtonTitle == "Done")
        #expect(success.showBackupButtonTitle == "Show Backup in Finder")
        #expect(success.message.contains("restored successfully"))
        #expect(success.message.contains(backupURL.path))
        #expect(success.previousBackupURL == backupURL)
    }

    @Test
    func explainsWhenThereWasNoPreviousDataToBackUp() {
        let success = AppDataRestoreSuccess(previousBackupURL: nil)

        #expect(success.message.contains("restored successfully"))
        #expect(success.message.contains("no previous app data to back up"))
        #expect(success.previousBackupURL == nil)
    }
}
