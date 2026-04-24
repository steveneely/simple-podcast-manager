import Foundation

public struct ManagedDirectoryResolver: Sendable {
    private let deviceLibrary: any DeviceLibraryInspecting

    public init(deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary()) {
        self.deviceLibrary = deviceLibrary
    }

    public func managedDirectoryURL(for subscription: FeedSubscription, on device: DeviceInfo) throws -> URL {
        let exactURL = device.musicURL.appendingPathComponent(subscription.title, isDirectory: true)
        let candidateDirectories = try deviceLibrary.directories(in: device.musicURL)
        if candidateDirectories.contains(where: { $0.standardizedFileURL == exactURL.standardizedFileURL }) {
            return exactURL
        }

        let matchingDirectories = candidateDirectories.filter {
            normalizedTitle($0.lastPathComponent) == normalizedTitle(subscription.title)
        }

        if matchingDirectories.count == 1 {
            return matchingDirectories[0]
        }

        return exactURL
    }

    private func normalizedTitle(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
