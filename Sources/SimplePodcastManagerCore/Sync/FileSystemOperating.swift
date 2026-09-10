import Foundation

public protocol FileSystemOperating: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func copyItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItem(at url: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func isRegularFile(at url: URL) throws -> Bool
    func isAppleDoubleFile(at url: URL) throws -> Bool
}

public struct LocalFileSystem: FileSystemOperating {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
    }

    public func isRegularFile(at url: URL) throws -> Bool {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.type] as? FileAttributeType == .typeRegular
    }

    public func isAppleDoubleFile(at url: URL) throws -> Bool {
        guard try isRegularFile(at: url) else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let header = try handle.read(upToCount: 26) ?? Data()
        // AppleDouble magic and version 2, followed by the entry descriptor table.
        guard header.count == 26,
              header.prefix(8) == Data([0, 5, 0x16, 7, 0, 2, 0, 0]) else { return false }
        let entryCount = Int(header[24]) * 256 + Int(header[25])
        guard entryCount > 0 else { return false }
        let tableSize = entryCount * 12
        let table = try handle.read(upToCount: tableSize) ?? Data()
        guard table.count == tableSize else { return false }
        for index in 0..<entryCount {
            let start = index * 12
            let offset = table[(start + 4)..<(start + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let length = table[(start + 8)..<(start + 12)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            guard offset >= UInt64(26 + tableSize), offset <= fileSize,
                  length <= fileSize - offset else { return false }
        }
        return true
    }
}
