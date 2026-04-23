import Foundation

public struct MountedVolumeResourceValues: Equatable, Sendable {
    public var volumeName: String?
    public var isDirectory: Bool
    public var isRemovable: Bool
    public var isEjectable: Bool

    public init(
        volumeName: String?,
        isDirectory: Bool,
        isRemovable: Bool,
        isEjectable: Bool
    ) {
        self.volumeName = volumeName
        self.isDirectory = isDirectory
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
    }
}
