import Foundation

struct AppDataRestoreSuccess: Equatable {
    let title = "Restore Complete"
    let doneButtonTitle = "Done"
    let showBackupButtonTitle = "Show Backup in Finder"
    let message: String
    let previousBackupURL: URL?

    init(previousBackupURL: URL?) {
        self.previousBackupURL = previousBackupURL

        if let previousBackupURL {
            message = "Your app data was restored successfully. A backup of your previous app data was saved at:\n\n\(previousBackupURL.path)"
        } else {
            message = "Your app data was restored successfully. There was no previous app data to back up."
        }
    }
}
