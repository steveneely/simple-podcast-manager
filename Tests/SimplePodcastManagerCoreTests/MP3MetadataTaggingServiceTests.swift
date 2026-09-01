import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct MP3MetadataTaggingServiceTests {
    @Test
    func writesRSSMetadataAndOptionalArtworkAsID3v23() throws {
        let audioData = Data([0xFF, 0xFB, 0x90, 0x64, 0x00])
        let artworkData = Data("jpeg-data".utf8)

        let taggedData = ID3MP3MetadataTaggingService.taggedMP3Data(
            sourceData: audioData,
            episodeTitle: "Correct Episode Title",
            podcastTitle: "Example Podcast",
            genre: "Podcast",
            artworkData: artworkData
        )

        #expect(Array(taggedData.prefix(3)) == Array("ID3".utf8))
        #expect(taggedData[3] == 0x03)
        #expect(taggedData.range(of: Data("APIC".utf8)) != nil)
        #expect(taggedData.range(of: Data("TIT2".utf8)) != nil)
        #expect(taggedData.range(of: Data("TALB".utf8)) != nil)
        #expect(taggedData.range(of: Data("TPE1".utf8)) != nil)
        #expect(taggedData.range(of: Data("TCON".utf8)) != nil)
        #expect(taggedData.contains(utf16Text("Correct Episode Title")))
        #expect(taggedData.contains(utf16Text("Example Podcast")))
        #expect(taggedData.contains(utf16Text("Podcast")))
        #expect(taggedData.contains(artworkData))
        #expect(taggedData.suffix(audioData.count) == audioData)
    }

    @Test
    func preservesOriginalUnicodeRSSMetadataInID3TextFrames() {
        let episodeTitle = "Das größte Hörspiel aus Łódź"
        let podcastTitle = "Hörspiele für große Hörer"

        let taggedData = ID3MP3MetadataTaggingService.taggedMP3Data(
            sourceData: Data([0xFF, 0xFB, 0x90, 0x64, 0x00]),
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            genre: "Hörspiel",
            artworkData: nil
        )

        #expect(taggedData.contains(utf16Text(episodeTitle)))
        #expect(taggedData.contains(utf16Text(podcastTitle)))
        #expect(taggedData.contains(utf16Text("Hörspiel")))
    }

    @Test
    func replacesPublisherMetadataWithRSSMetadata() throws {
        let placeholder = "Title Placeholder Episode ID: 122792502"
        let publisherTitleFrame = makeTextFrame(id: "TIT2", text: placeholder)
        let publisherCommentFrame = makeFrame(id: "COMM", payload: Data("publisher comment".utf8))
        let sourceData = makeID3Tag(frames: publisherTitleFrame + publisherCommentFrame)
            + Data([0xFF, 0xFB, 0x90, 0x64, 0x00])

        let taggedData = ID3MP3MetadataTaggingService.taggedMP3Data(
            sourceData: sourceData,
            episodeTitle: "Why a Nation Can't Outsource Its Frontier AI",
            podcastTitle: "Machine Learning Street Talk (MLST)",
            genre: "Podcast",
            artworkData: nil
        )

        #expect(taggedData.contains(utf16Text("Why a Nation Can't Outsource Its Frontier AI")))
        #expect(taggedData.range(of: Data(placeholder.utf8)) == nil)
        #expect(taggedData.range(of: Data("COMM".utf8)) == nil)
    }

    @Test
    func writesMetadataWhenArtworkIsUnavailable() throws {
        let audioData = Data([0xFF, 0xFB, 0x90, 0x64, 0x00])

        let taggedData = ID3MP3MetadataTaggingService.taggedMP3Data(
            sourceData: audioData,
            episodeTitle: "Episode Without Artwork",
            podcastTitle: "Example Podcast",
            genre: "Podcast",
            artworkData: nil
        )

        #expect(taggedData.range(of: Data("APIC".utf8)) == nil)
        #expect(taggedData.contains(utf16Text("Episode Without Artwork")))
        #expect(taggedData.suffix(audioData.count) == audioData)
    }

    @Test
    func removesTrailingID3v1MetadataToAvoidConflictingTitles() throws {
        let audioData = Data([0xFF, 0xFB, 0x90, 0x64, 0x00])
        var id3v1Tag = Data("TAGOld title".utf8)
        id3v1Tag.append(Data(repeating: 0, count: 128 - id3v1Tag.count))

        let taggedData = ID3MP3MetadataTaggingService.taggedMP3Data(
            sourceData: audioData + id3v1Tag,
            episodeTitle: "Correct Title",
            podcastTitle: "Example Podcast",
            genre: "Podcast",
            artworkData: nil
        )

        #expect(taggedData.suffix(audioData.count) == audioData)
        #expect(taggedData.range(of: Data("Old title".utf8)) == nil)
    }

    private func utf16Text(_ text: String) -> Data {
        Data([0x01, 0xFF, 0xFE]) + (text.data(using: .utf16LittleEndian) ?? Data())
    }

    private func makeTextFrame(id: String, text: String) -> Data {
        makeFrame(id: id, payload: Data([0x00]) + Data(text.utf8))
    }

    private func makeFrame(id: String, payload: Data) -> Data {
        var frame = Data(id.utf8)
        frame.append(contentsOf: UInt32(payload.count).bigEndianBytes)
        frame.append(contentsOf: [0x00, 0x00])
        frame.append(payload)
        return frame
    }

    private func makeID3Tag(frames: Data) -> Data {
        var tag = Data("ID3".utf8)
        tag.append(contentsOf: [0x03, 0x00, 0x00])
        tag.append(contentsOf: [0x00, 0x00, 0x00, UInt8(frames.count)])
        tag.append(frames)
        return tag
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
