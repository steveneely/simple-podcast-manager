import Foundation

public struct DeviceInfo: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var rootURL: URL
    public var podcastDirectoryURL: URL

    public var id: String {
        rootURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public init(
        name: String,
        rootURL: URL,
        podcastDirectoryURL: URL
    ) {
        self.name = name
        self.rootURL = rootURL
        self.podcastDirectoryURL = podcastDirectoryURL
    }
}
