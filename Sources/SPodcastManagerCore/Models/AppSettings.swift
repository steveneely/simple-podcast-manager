import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var ffmpegExecutablePath: String?
    public var dryRunByDefault: Bool
    public var ejectAfterSyncByDefault: Bool

    public init(
        ffmpegExecutablePath: String? = nil,
        dryRunByDefault: Bool = true,
        ejectAfterSyncByDefault: Bool = false
    ) {
        self.ffmpegExecutablePath = ffmpegExecutablePath
        self.dryRunByDefault = dryRunByDefault
        self.ejectAfterSyncByDefault = ejectAfterSyncByDefault
    }
}
