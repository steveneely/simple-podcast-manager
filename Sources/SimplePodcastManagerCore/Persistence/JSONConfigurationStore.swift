import Foundation

public struct JSONConfigurationStore: ConfigurationStore {
    public let fileURL: URL

    public init(
        fileURL: URL
    ) {
        self.fileURL = fileURL
    }

    public func loadConfiguration() throws -> AppConfiguration {
        try AppJSONFile.load(AppConfiguration.self, from: fileURL, defaultValue: AppConfiguration())
    }

    public func saveConfiguration(_ configuration: AppConfiguration) throws {
        try AppJSONFile.save(configuration, to: fileURL)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "config.json", directoryHint: .notDirectory)
    }
}
