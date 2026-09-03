import Foundation

public enum DeviceAudioFile {
    private static let supportedExtensions = Set([
        "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma"
    ])

    public static func isSupported(_ fileURL: URL) -> Bool {
        supportedExtensions.contains(fileURL.pathExtension.lowercased())
            && !fileURL.lastPathComponent.hasPrefix("._")
    }
}
