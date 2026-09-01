import Foundation

public protocol MP3MetadataTaggingService: Sendable {
    func writeMetadata(
        sourceFileURL: URL,
        episodeTitle: String,
        podcastTitle: String,
        genre: String,
        artworkFileURL: URL?,
        destinationFileURL: URL
    ) throws
}

/// Writes a small, predictable ID3v2.3 tag instead of trusting metadata from
/// podcast publishers. The RSS feed is the source of truth for display names.
public struct ID3MP3MetadataTaggingService: MP3MetadataTaggingService {
    public init() {}

    public func writeMetadata(
        sourceFileURL: URL,
        episodeTitle: String,
        podcastTitle: String,
        genre: String,
        artworkFileURL: URL?,
        destinationFileURL: URL
    ) throws {
        let sourceData = try Data(contentsOf: sourceFileURL)
        let artworkData = try artworkFileURL.map { try Data(contentsOf: $0) }
        let taggedData = Self.taggedMP3Data(
            sourceData: sourceData,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            genre: genre,
            artworkData: artworkData
        )

        try FileManager.default.createDirectory(
            at: destinationFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try taggedData.write(to: destinationFileURL, options: .atomic)
    }

    static func taggedMP3Data(
        sourceData: Data,
        episodeTitle: String,
        podcastTitle: String,
        genre: String,
        artworkData: Data?
    ) -> Data {
        var frames = Data()

        // Artwork comes first for compatibility with simple hardware players.
        if let artworkData {
            frames.append(makeArtworkFrame(artworkData))
        }
        frames.append(makeTextFrame(id: "TIT2", text: episodeTitle))
        frames.append(makeTextFrame(id: "TALB", text: podcastTitle))
        frames.append(makeTextFrame(id: "TPE1", text: podcastTitle))
        let normalizedGenre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedGenre.isEmpty {
            frames.append(makeTextFrame(id: "TCON", text: normalizedGenre))
        }

        var taggedData = makeID3v23Tag(frames: frames)
        taggedData.append(sourceData.audioDataWithoutMetadataTags())
        return taggedData
    }

    private static func makeID3v23Tag(frames: Data) -> Data {
        var tag = Data("ID3".utf8)
        tag.append(contentsOf: [0x03, 0x00]) // ID3v2.3.0
        tag.append(0x00) // flags
        tag.append(contentsOf: synchsafeBytes(for: frames.count))
        tag.append(frames)
        return tag
    }

    private static func makeTextFrame(id: String, text: String) -> Data {
        var payload = Data([0x01, 0xFF, 0xFE]) // UTF-16 with little-endian BOM
        payload.append(text.data(using: .utf16LittleEndian) ?? Data())
        return makeFrame(id: id, payload: payload)
    }

    private static func makeArtworkFrame(_ artworkData: Data) -> Data {
        var payload = Data()
        payload.append(0x00) // ISO-8859-1 text encoding
        payload.append(Data("image/jpeg".utf8))
        payload.append(0x00)
        payload.append(0x03) // front cover
        payload.append(0x00) // empty description
        payload.append(artworkData)
        return makeFrame(id: "APIC", payload: payload)
    }

    private static func makeFrame(id: String, payload: Data) -> Data {
        var frame = Data(id.utf8)
        frame.append(contentsOf: UInt32(payload.count).bigEndianBytes)
        frame.append(contentsOf: [0x00, 0x00]) // flags
        frame.append(payload)
        return frame
    }

    private static func synchsafeBytes(for value: Int) -> [UInt8] {
        [
            UInt8((value >> 21) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8(value & 0x7F),
        ]
    }
}

private extension Data {
    func audioDataWithoutMetadataTags() -> Data {
        strippingLeadingID3v2Tag().strippingTrailingID3v1Tag()
    }

    func strippingLeadingID3v2Tag() -> Data {
        guard count >= 10, self[0] == 0x49, self[1] == 0x44, self[2] == 0x33 else {
            return self
        }

        let tagSize = Int(self[6] & 0x7F) << 21
            | Int(self[7] & 0x7F) << 14
            | Int(self[8] & 0x7F) << 7
            | Int(self[9] & 0x7F)
        let hasFooter = (self[5] & 0x10) != 0
        let totalTagSize = 10 + tagSize + (hasFooter ? 10 : 0)

        guard totalTagSize <= count else { return self }
        return Data(self[totalTagSize...])
    }

    func strippingTrailingID3v1Tag() -> Data {
        guard count >= 128, suffix(128).starts(with: Data("TAG".utf8)) else {
            return self
        }
        return Data(dropLast(128))
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
