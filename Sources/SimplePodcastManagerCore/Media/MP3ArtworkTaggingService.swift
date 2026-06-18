import Foundation

public protocol MP3ArtworkTaggingService: Sendable {
    func writeArtwork(sourceFileURL: URL, artworkFileURL: URL, destinationFileURL: URL) throws
}

public struct ID3MP3ArtworkTaggingService: MP3ArtworkTaggingService {
    public init() {}

    public func writeArtwork(sourceFileURL: URL, artworkFileURL: URL, destinationFileURL: URL) throws {
        let sourceData = try Data(contentsOf: sourceFileURL)
        let artworkData = try Data(contentsOf: artworkFileURL)
        let taggedData = Self.taggedMP3Data(sourceData: sourceData, artworkData: artworkData)

        try FileManager.default.createDirectory(
            at: destinationFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try taggedData.write(to: destinationFileURL, options: .atomic)
    }

    static func taggedMP3Data(sourceData: Data, artworkData: Data) -> Data {
        let existingTag = sourceData.existingID3v2TagWithoutArtworkFrames()
        var taggedData = makeID3v23Tag(
            preservedFrames: existingTag?.frames ?? Data(),
            artworkData: artworkData
        )
        taggedData.append(existingTag?.audioData ?? sourceData.strippingLeadingID3v2Tag())
        return taggedData
    }

    private static func makeID3v23Tag(preservedFrames: Data, artworkData: Data) -> Data {
        let frame = makeAPICFrame(artworkData: artworkData)
        var frames = preservedFrames
        frames.append(frame)

        var tag = Data()
        tag.append(contentsOf: [0x49, 0x44, 0x33]) // ID3
        tag.append(contentsOf: [0x03, 0x00]) // ID3v2.3.0
        tag.append(0x00) // flags
        tag.append(contentsOf: synchsafeBytes(for: frames.count))
        tag.append(frames)
        return tag
    }

    private static func makeAPICFrame(artworkData: Data) -> Data {
        var payload = Data()
        payload.append(0x00) // ISO-8859-1 text encoding
        payload.append(Data("image/jpeg".utf8))
        payload.append(0x00)
        payload.append(0x03) // front cover
        payload.append(0x00) // empty description
        payload.append(artworkData)

        var frame = Data()
        frame.append(Data("APIC".utf8))
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
    struct ExistingID3v2Tag {
        var frames: Data
        var audioData: Data
    }

    func existingID3v2TagWithoutArtworkFrames() -> ExistingID3v2Tag? {
        guard
            count >= 10,
            self[0] == 0x49,
            self[1] == 0x44,
            self[2] == 0x33,
            self[3] == 0x03 || self[3] == 0x04,
            self[5] == 0x00
        else {
            return nil
        }

        let tagSize = leadingID3v2TagSize
        let totalTagSize = 10 + tagSize
        guard totalTagSize < count else {
            return nil
        }

        let tagBody = self[10..<totalTagSize]
        var offset = tagBody.startIndex
        var preservedFrames = Data()

        while offset + 10 <= tagBody.endIndex {
            let frameIDData = tagBody[offset..<offset + 4]
            if frameIDData.allSatisfy({ $0 == 0x00 }) {
                break
            }

            guard let frameID = String(data: frameIDData, encoding: .isoLatin1) else {
                return nil
            }

            let sizeStart = offset + 4
            let frameSize = self[3] == 0x04
                ? tagBody.synchsafeInteger(at: sizeStart)
                : tagBody.bigEndianInteger(at: sizeStart)
            let frameEnd = offset + 10 + frameSize
            guard frameSize >= 0, frameEnd <= tagBody.endIndex else {
                return nil
            }

            if frameID != "APIC" {
                preservedFrames.append(tagBody[offset..<frameEnd])
            }
            offset = frameEnd
        }

        return ExistingID3v2Tag(
            frames: preservedFrames,
            audioData: self[totalTagSize...]
        )
    }

    func strippingLeadingID3v2Tag() -> Data {
        guard count >= 10, self[0] == 0x49, self[1] == 0x44, self[2] == 0x33 else {
            return self
        }

        let tagSize = leadingID3v2TagSize
        let hasFooter = (self[5] & 0x10) != 0
        let totalTagSize = 10 + tagSize + (hasFooter ? 10 : 0)

        guard totalTagSize < count else {
            return self
        }

        return self[totalTagSize...]
    }

    var leadingID3v2TagSize: Int {
        Int(self[6] & 0x7F) << 21
            | Int(self[7] & 0x7F) << 14
            | Int(self[8] & 0x7F) << 7
            | Int(self[9] & 0x7F)
    }

    func synchsafeInteger(at index: Int) -> Int {
        Int(self[index] & 0x7F) << 21
            | Int(self[index + 1] & 0x7F) << 14
            | Int(self[index + 2] & 0x7F) << 7
            | Int(self[index + 3] & 0x7F)
    }

    func bigEndianInteger(at index: Int) -> Int {
        Int(self[index]) << 24
            | Int(self[index + 1]) << 16
            | Int(self[index + 2]) << 8
            | Int(self[index + 3])
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
