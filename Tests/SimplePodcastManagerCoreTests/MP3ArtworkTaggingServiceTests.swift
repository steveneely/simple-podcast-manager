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
        let existingFrame = Data("TIT2".utf8) + Data([0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
        let existingArtworkFrame = Data("APIC".utf8) + Data([0x00, 0x00, 0x00, 0x0E, 0x00, 0x00]) + Data([0x00]) + Data("image/jpeg".utf8) + Data([0x00, 0x03, 0x00, 0x01])
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
}
