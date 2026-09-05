import Foundation

public enum AudioConversionError: LocalizedError, Equatable, Sendable {
    case ffmpegNotConfigured
    case conversionFailed(exitCode: Int32, output: String)
    case metadataWritingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .ffmpegNotConfigured:
            return "FFmpeg is required to convert non-MP3 audio. Install FFmpeg, then select its executable in Settings."
        case .conversionFailed(let exitCode, let output):
            return "ffmpeg failed with exit code \(exitCode): \(output)"
        case .metadataWritingFailed(let detail):
            return "The MP3 metadata could not be written: \(detail)"
        }
    }
}
