import Foundation

public struct DeviceInfo: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var rootURL: URL
    public var musicURL: URL

    public var id: String {
        rootURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public init(
        name: String,
        rootURL: URL,
        musicURL: URL
    ) {
        self.name = name
        self.rootURL = rootURL
        self.musicURL = musicURL
    }
}
