import Foundation

public struct PodcastDirectoryCredentials: Codable, Equatable, Sendable {
    public var apiKey: String
    public var apiSecret: String

    public init(apiKey: String, apiSecret: String) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
    }

    public var isValid: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
