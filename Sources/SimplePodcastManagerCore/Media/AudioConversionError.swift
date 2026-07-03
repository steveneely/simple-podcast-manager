import Foundation

public enum AudioConversionError: LocalizedError, Equatable, Sendable {
    case ffmpegNotConfigured
    case conversionFailed(exitCode: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .ffmpegNotConfigured:
            return "ffmpeg is required to convert non-MP3 audio. Set the ffmpeg path in Settings."
        case .conversionFailed(let exitCode, let output):
            return "ffmpeg failed with exit code \(exitCode): \(output)"
        }
    }
}
