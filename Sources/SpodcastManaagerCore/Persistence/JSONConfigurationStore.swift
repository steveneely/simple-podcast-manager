import Foundation

public struct JSONConfigurationStore: ConfigurationStore {
    public let fileURL: URL

    public init(
        fileURL: URL
    ) {
        self.fileURL = fileURL
    }

    public func loadConfiguration() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppConfiguration()
        }

        let data = try Data(contentsOf: fileURL)
        return try Self.makeDecoder().decode(AppConfiguration.self, from: data)
    }

    public func saveConfiguration(_ configuration: AppConfiguration) throws {
        let parentDirectoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        let data = try Self.makeEncoder().encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "config.json", directoryHint: .notDirectory)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
