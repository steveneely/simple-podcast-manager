import Foundation

public struct DeviceInfo: Codable, Equatable, Sendable {
    public var name: String
    public var rootURL: URL
    public var musicURL: URL
    public var trashURL: URL

    public init(
        name: String,
        rootURL: URL,
        musicURL: URL,
        trashURL: URL
    ) {
        self.name = name
        self.rootURL = rootURL
        self.musicURL = musicURL
        self.trashURL = trashURL
    }
}
