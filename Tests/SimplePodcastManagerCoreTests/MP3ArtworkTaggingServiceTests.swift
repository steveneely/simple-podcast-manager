import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct MP3ArtworkTaggingServiceTests {
    @Test
    func writesID3v23FrontCoverArtworkFrame() throws {
        let sourceData = Data([0xFF, 0xFB, 0x90, 0x64, 0x00])
        let artworkData = Data("jpeg-data".utf8)

        let taggedData = ID3MP3ArtworkTaggingService.taggedMP3Data(
            sourceData: sourceData,
            artworkData: artworkData
        )

        #expect(Array(taggedData.prefix(3)) == Array("ID3".utf8))
        #expect(taggedData[3] == 0x03)
        #expect(taggedData[4] == 0x00)
        #expect(Array(taggedData[10..<14]) == Array("APIC".utf8))
        #expect(taggedData.contains(Data("image/jpeg".utf8)))
        #expect(taggedData.contains(artworkData))
        #expect(taggedData.suffix(sourceData.count) == sourceData)
    }

    @Test
    func preservesExistingID3FramesAndReplacesArtworkFrame() throws {
        let existingFrame = makeFrame(id: "TIT2", payload: Data([0x00]))
        let existingArtworkFrame = makeFrame(
            id: "APIC",
            payload: Data([0x00]) + Data("image/jpeg".utf8) + Data([0x00, 0x03, 0x00, 0x01])
        )
        let existingFrames = existingFrame + existingArtworkFrame
        var existingTag = Data("ID3".utf8)
        existingTag.append(contentsOf: [0x03, 0x00, 0x00])
        existingTag.append(contentsOf: [0x00, 0x00, 0x00, UInt8(existingFrames.count)])
        existingTag.append(existingFrames)
        let audioData = Data([0xFF, 0xFB, 0x90, 0x64, 0x00])

        let taggedData = ID3MP3ArtworkTaggingService.taggedMP3Data(
            sourceData: existingTag + audioData,
            artworkData: Data("jpeg-data".utf8)
        )

        #expect(taggedData.suffix(audioData.count) == audioData)
        #expect(taggedData.range(of: Data("TIT2".utf8)) != nil)
        #expect(taggedData.range(of: Data([0x00, 0x03, 0x00, 0x01])) == nil)
    }

    @Test
    func writesArtworkBeforePreservedFramesForDeviceCompatibility() throws {
        let existingFrame = makeFrame(id: "TIT2", payload: Data([0x00]))
        var existingTag = Data("ID3".utf8)
        existingTag.append(contentsOf: [0x03, 0x00, 0x00])
        existingTag.append(contentsOf: [0x00, 0x00, 0x00, UInt8(existingFrame.count)])
        existingTag.append(existingFrame)
        let audioData = Data([0xFF, 0xFB, 0x90, 0x64, 0x00])

        let taggedData = ID3MP3ArtworkTaggingService.taggedMP3Data(
            sourceData: existingTag + audioData,
            artworkData: Data("jpeg-data".utf8)
        )

        let artworkRange = try #require(taggedData.range(of: Data("APIC".utf8)))
        let titleRange = try #require(taggedData.range(of: Data("TIT2".utf8)))
        #expect(artworkRange.lowerBound < titleRange.lowerBound)
    }

    @Test
    func dropsChapterFramesWhenAddingArtwork() throws {
        let titleFrame = makeFrame(id: "TIT2", payload: Data([0x00]))
        let chapterFrame = makeFrame(id: "CHAP", payload: Data("chapter-data".utf8))
        let tableOfContentsFrame = makeFrame(id: "CTOC", payload: Data("toc-data".utf8))
        let existingFrames = chapterFrame + tableOfContentsFrame + titleFrame
        var existingTag = Data("ID3".utf8)
        existingTag.append(contentsOf: [0x03, 0x00, 0x00])
        existingTag.append(contentsOf: [0x00, 0x00, 0x00, UInt8(existingFrames.count)])
        existingTag.append(existingFrames)
        let audioData = Data([0xFF, 0xFB, 0x90, 0x64, 0x00])

        let taggedData = ID3MP3ArtworkTaggingService.taggedMP3Data(
            sourceData: existingTag + audioData,
            artworkData: Data("jpeg-data".utf8)
        )

        #expect(taggedData.range(of: Data("CHAP".utf8)) == nil)
        #expect(taggedData.range(of: Data("CTOC".utf8)) == nil)
        #expect(taggedData.range(of: Data("TIT2".utf8)) != nil)
        #expect(taggedData.suffix(audioData.count) == audioData)
    }

    private func makeFrame(id: String, payload: Data) -> Data {
        var frame = Data(id.utf8)
        frame.append(contentsOf: UInt32(payload.count).bigEndianBytes)
        frame.append(contentsOf: [0x00, 0x00])
        frame.append(payload)
        return frame
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF),
        ]
    }
}
