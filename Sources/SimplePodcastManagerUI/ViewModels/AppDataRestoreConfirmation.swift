import Foundation

struct AppDataRestoreConfirmation: Equatable {
    let title = "Restore App Data?"
    let cancelButtonTitle = "Cancel"
    let restoreButtonTitle = "Restore"
    let message: String

    init(backupURL: URL) {
        message = "Restoring \(backupURL.lastPathComponent) replaces your podcasts, settings, and episode history. Your current app data will be backed up first. Downloaded audio files will not be deleted."
    }
}
