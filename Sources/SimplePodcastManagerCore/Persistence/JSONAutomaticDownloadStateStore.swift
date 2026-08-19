import Foundation

public struct JSONAutomaticDownloadStateStore: AutomaticDownloadStateStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadState() throws -> AutomaticDownloadState {
        try AppJSONFile.load(AutomaticDownloadState.self, from: fileURL, defaultValue: AutomaticDownloadState())
    }

    public func saveState(_ state: AutomaticDownloadState) throws {
        try AppJSONFile.save(state, to: fileURL)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "automatic-downloads.json", directoryHint: .notDirectory)
    }
}
