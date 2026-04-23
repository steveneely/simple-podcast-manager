import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var ffmpegExecutablePath: String?
    public var podcastIndexAPIKey: String?
    public var podcastIndexAPISecret: String?
    public var dryRunByDefault: Bool
    public var ejectAfterSyncByDefault: Bool

    public init(
        ffmpegExecutablePath: String? = nil,
        podcastIndexAPIKey: String? = nil,
        podcastIndexAPISecret: String? = nil,
        dryRunByDefault: Bool = true,
        ejectAfterSyncByDefault: Bool = false
    ) {
        self.ffmpegExecutablePath = ffmpegExecutablePath
        self.podcastIndexAPIKey = podcastIndexAPIKey
        self.podcastIndexAPISecret = podcastIndexAPISecret
        self.dryRunByDefault = dryRunByDefault
        self.ejectAfterSyncByDefault = ejectAfterSyncByDefault
    }
}
