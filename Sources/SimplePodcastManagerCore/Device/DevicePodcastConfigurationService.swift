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
            return (try? DevicePodcastConfiguration(podcastDirectoryPath: relativePodcastDirectoryPath(on: device)))
                ?? DevicePodcastConfiguration.defaultConfiguration
        }

        return configuration
    }

    public func savePodcastDirectoryPath(_ path: String, on device: DeviceInfo) throws -> DeviceInfo {
        let (configuration, updatedDevice) = try configuredDevice(for: path, on: device)

        try validateConfigurationWrite(on: updatedDevice)
        try fileSystem.createDirectory(at: updatedDevice.podcastDirectoryURL)
        try fileSystem.writeString(configuration.contents, to: configurationURL(on: updatedDevice))

        return updatedDevice
    }

    public func podcastDirectoryExists(_ path: String, on device: DeviceInfo) throws -> Bool {
        let (_, updatedDevice) = try configuredDevice(for: path, on: device)
        try validateConfigurationWrite(on: updatedDevice)
        return fileSystem.directoryExists(at: updatedDevice.podcastDirectoryURL)
    }

    public func relativePodcastDirectoryPath(on device: DeviceInfo) -> String {
        let rootPath = device.rootURL.standardizedFileURL.path
        let podcastDirectoryPath = device.podcastDirectoryURL.standardizedFileURL.path
        guard podcastDirectoryPath.hasPrefix(rootPath + "/") else {
            return DevicePodcastConfiguration.defaultPodcastDirectoryPath
        }

        return String(podcastDirectoryPath.dropFirst(rootPath.count + 1))
    }

    private func configurationURL(on device: DeviceInfo) -> URL {
        device.rootURL
            .appending(path: DevicePodcastConfiguration.fileName, directoryHint: .notDirectory)
            .standardizedFileURL
    }

    private func configuredDevice(for path: String, on device: DeviceInfo) throws -> (DevicePodcastConfiguration, DeviceInfo) {
        let configuration = try DevicePodcastConfiguration(podcastDirectoryPath: path)
        let podcastDirectoryURL = device.rootURL
            .appending(path: configuration.podcastDirectoryPath, directoryHint: .isDirectory)
            .standardizedFileURL

        return (
            configuration,
            DeviceInfo(
                name: device.name,
                rootURL: device.rootURL,
                podcastDirectoryURL: podcastDirectoryURL
            )
        )
    }

    private func validateConfigurationWrite(on device: DeviceInfo) throws {
        let rootURL = device.rootURL.resolvingSymlinksInPath().standardizedFileURL
        let configURL = configurationURL(on: device).resolvingSymlinksInPath().standardizedFileURL
        let podcastDirectoryURL = device.podcastDirectoryURL.resolvingSymlinksInPath().standardizedFileURL

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
