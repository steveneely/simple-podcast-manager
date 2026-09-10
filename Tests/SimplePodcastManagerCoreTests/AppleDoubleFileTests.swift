import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct AppleDoubleFileTests {
    @Test
    func recognizesSidecarWithoutChangingAudioOrEmbeddedMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("episode.mp3")
        let sidecar = directory.appendingPathComponent("._episode.mp3")
        let audioBytes = Data("ID3 embedded title and artwork followed by audio".utf8)
        try audioBytes.write(to: audio)
        try appleDoubleData().write(to: sidecar)
        let fileSystem = LocalFileSystem()
        #expect(try fileSystem.isAppleDoubleFile(at: sidecar))
        try fileSystem.removeItem(at: sidecar)
        #expect(try Data(contentsOf: audio) == audioBytes)
    }

    @Test
    func rejectsUnrecognizedTruncatedAndOutOfBoundsSidecars() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("._episode.mp3")
        var wrongVersion = appleDoubleData()
        wrongVersion[5] = 9
        var outOfBounds = appleDoubleData()
        outOfBounds[37] = 99
        let invalidFiles = [Data(), Data("not metadata".utf8), Data(appleDoubleData().prefix(8)), Data(appleDoubleData().prefix(26)), wrongVersion, outOfBounds]
        for data in invalidFiles {
            try data.write(to: target)
            #expect(try !LocalFileSystem().isAppleDoubleFile(at: target))
            #expect(try Data(contentsOf: target) == data)
        }
    }

    @Test
    func rejectsDirectoriesAndSymbolicLinksEvenToValidSidecars() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("metadata")
        let link = directory.appendingPathComponent("._episode.mp3")
        try appleDoubleData().write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(try !LocalFileSystem().isRegularFile(at: directory))
        #expect(try !LocalFileSystem().isRegularFile(at: link))
        #expect(try !LocalFileSystem().isAppleDoubleFile(at: directory))
        #expect(try !LocalFileSystem().isAppleDoubleFile(at: link))
        #expect(try Data(contentsOf: target) == appleDoubleData())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func appleDoubleData() -> Data {
        // Version 2, one resource-fork descriptor pointing to four payload bytes.
        Data([0, 5, 0x16, 7, 0, 2, 0, 0] + Array(repeating: UInt8(0), count: 16)
             + [0, 1, 0, 0, 0, 2, 0, 0, 0, 38, 0, 0, 0, 4, 1, 2, 3, 4])
    }
}
