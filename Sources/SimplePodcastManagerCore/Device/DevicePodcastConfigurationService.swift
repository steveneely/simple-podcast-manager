import Foundation

public struct DevicePodcastConfigurationService: Sendable {
    private let fileSystem: any DevicePodcastConfigurationFileSystem

    public init(fileSystem: any DevicePodcastConfigurationFileSystem = LocalDevicePodcastConfigurationFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func loadConfiguration(on device: DeviceInfo) -> DevicePodcastConfiguration {
        let configURL = configurationURL(on: device)
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8),
              let configuration = try? DevicePodcastConfiguration(contents: contents) else {
            let playlistDirectoryPath = device.playlistDirectoryURL.standardizedFileURL
                == device.podcastDirectoryURL.standardizedFileURL
                ? nil
                : relativePlaylistDirectoryPath(on: device)
            return (try? DevicePodcastConfiguration(
                podcastDirectoryPath: relativePodcastDirectoryPath(on: device),
                playlistDirectoryPath: playlistDirectoryPath
            ))
                ?? DevicePodcastConfiguration.defaultConfiguration
        }

        return configuration
    }

    public func savePodcastDirectoryPath(_ path: String, on device: DeviceInfo) throws -> DeviceInfo {
        let currentConfiguration = loadConfiguration(on: device)
        return try saveDirectoryPaths(
            podcastDirectoryPath: path,
            playlistDirectoryPath: currentConfiguration.playlistDirectoryPath,
            on: device
        )
    }

    public func saveDirectoryPaths(
        podcastDirectoryPath: String,
        playlistDirectoryPath: String?,
        on device: DeviceInfo
    ) throws -> DeviceInfo {
        let configuration = try DevicePodcastConfiguration(
            podcastDirectoryPath: podcastDirectoryPath,
            playlistDirectoryPath: playlistDirectoryPath
        )
        let updatedDevice = configuredDevice(for: configuration, on: device)

        try validateConfigurationWrite(on: updatedDevice)
        try fileSystem.createDirectory(at: updatedDevice.podcastDirectoryURL)
        if updatedDevice.playlistDirectoryURL != updatedDevice.podcastDirectoryURL {
            try fileSystem.createDirectory(at: updatedDevice.playlistDirectoryURL)
        }
        try fileSystem.writeString(configuration.contents, to: configurationURL(on: updatedDevice))

        return updatedDevice
    }

    public func podcastDirectoryExists(_ path: String, on device: DeviceInfo) throws -> Bool {
        let configuration = try DevicePodcastConfiguration(podcastDirectoryPath: path)
        let updatedDevice = configuredDevice(for: configuration, on: device)
        try validateConfigurationWrite(on: updatedDevice)
        return fileSystem.directoryExists(at: updatedDevice.podcastDirectoryURL)
    }

    public func playlistDirectoryExists(_ path: String, on device: DeviceInfo) throws -> Bool {
        let configuration = try DevicePodcastConfiguration(
            podcastDirectoryPath: relativePodcastDirectoryPath(on: device),
            playlistDirectoryPath: path
        )
        let updatedDevice = configuredDevice(for: configuration, on: device)
        try validateConfigurationWrite(on: updatedDevice)
        return fileSystem.directoryExists(at: updatedDevice.playlistDirectoryURL)
    }

    public func relativePodcastDirectoryPath(on device: DeviceInfo) -> String {
        relativeDirectoryPath(
            device.podcastDirectoryURL,
            on: device,
            fallback: DevicePodcastConfiguration.defaultPodcastDirectoryPath
        )
    }

    public func relativePlaylistDirectoryPath(on device: DeviceInfo) -> String {
        relativeDirectoryPath(
            device.playlistDirectoryURL,
            on: device,
            fallback: relativePodcastDirectoryPath(on: device)
        )
    }

    private func configurationURL(on device: DeviceInfo) -> URL {
        device.rootURL
            .appending(path: DevicePodcastConfiguration.fileName, directoryHint: .notDirectory)
            .standardizedFileURL
    }

    private func configuredDevice(
        for configuration: DevicePodcastConfiguration,
        on device: DeviceInfo
    ) -> DeviceInfo {
        let podcastDirectoryURL = device.rootURL
            .appending(path: configuration.podcastDirectoryPath, directoryHint: .isDirectory)
            .standardizedFileURL
        let playlistDirectoryURL = device.rootURL
            .appending(path: configuration.resolvedPlaylistDirectoryPath, directoryHint: .isDirectory)
            .standardizedFileURL

        return DeviceInfo(
            name: device.name,
            rootURL: device.rootURL,
            podcastDirectoryURL: podcastDirectoryURL,
            playlistDirectoryURL: playlistDirectoryURL
        )
    }

    private func validateConfigurationWrite(on device: DeviceInfo) throws {
        let rootURL = device.rootURL.resolvingSymlinksInPath().standardizedFileURL
        let configURL = configurationURL(on: device).resolvingSymlinksInPath().standardizedFileURL
        let podcastDirectoryURL = device.podcastDirectoryURL.resolvingSymlinksInPath().standardizedFileURL
        let playlistDirectoryURL = device.playlistDirectoryURL.resolvingSymlinksInPath().standardizedFileURL

        guard rootURL.path.hasPrefix("/Volumes/") else {
            throw SafetyValidationError.invalidDeviceRoot(rootURL)
        }

        guard configURL.deletingLastPathComponent().standardizedFileURL == rootURL,
              configURL.lastPathComponent == DevicePodcastConfiguration.fileName else {
            throw SafetyValidationError.pathOutsideDeviceRoot(configURL)
        }

        let rootDirectoryPath = rootURL.appendingPathComponent("", isDirectory: true).path
        guard podcastDirectoryURL.path.hasPrefix(rootDirectoryPath),
              podcastDirectoryURL != rootURL else {
            throw SafetyValidationError.invalidPodcastDirectory(podcastDirectoryURL)
        }
        guard playlistDirectoryURL.path.hasPrefix(rootDirectoryPath),
              playlistDirectoryURL != rootURL else {
            throw SafetyValidationError.invalidPlaylistDirectory(playlistDirectoryURL)
        }
    }

    private func relativeDirectoryPath(
        _ directoryURL: URL,
        on device: DeviceInfo,
        fallback: String
    ) -> String {
        let rootPath = device.rootURL.standardizedFileURL.path
        let directoryPath = directoryURL.standardizedFileURL.path
        guard directoryPath.hasPrefix(rootPath + "/") else { return fallback }
        return String(directoryPath.dropFirst(rootPath.count + 1))
    }
}

public protocol DevicePodcastConfigurationFileSystem: Sendable {
    func directoryExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func writeString(_ string: String, to url: URL) throws
}

public struct LocalDevicePodcastConfigurationFileSystem: DevicePodcastConfigurationFileSystem {
    public init() {}

    public func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func writeString(_ string: String, to url: URL) throws {
        try string.write(to: url, atomically: true, encoding: .utf8)
    }
}
