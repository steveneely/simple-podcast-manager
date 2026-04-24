import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var ffmpegExecutablePath: String?

    public init(
        ffmpegExecutablePath: String? = nil
    ) {
        self.ffmpegExecutablePath = ffmpegExecutablePath
    }
}
