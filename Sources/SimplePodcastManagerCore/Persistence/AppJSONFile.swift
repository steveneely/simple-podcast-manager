import Foundation

/// Shared JSON file mechanics used by the app's small, type-specific stores.
enum AppJSONFile {
    static func load<Value: Decodable>(
        _ type: Value.Type,
        from fileURL: URL,
        defaultValue: @autoclosure () -> Value
    ) throws -> Value {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return defaultValue()
        }
        return try decode(type, from: fileURL)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from fileURL: URL) throws -> Value {
        let data = try Data(contentsOf: fileURL)
        return try AppJSONCoding.makeDecoder().decode(type, from: data)
    }

    static func save<Value: Encodable>(_ value: Value, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try AppJSONCoding.makeEncoder().encode(value)
        try data.write(to: fileURL, options: .atomic)
    }
}
