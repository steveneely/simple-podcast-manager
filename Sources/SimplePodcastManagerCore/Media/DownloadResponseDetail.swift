import Foundation

/// Extracts a short server explanation without displaying whole error pages or response metadata.
enum DownloadResponseDetail {
    static let maximumBodyBytes = 16_384
    static let maximumDetailCharacters = 500

    static func read(from fileURL: URL) -> Data? {
        guard let file = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? file.close() }
        return try? file.read(upToCount: maximumBodyBytes)
    }

    static func extract(from data: Data?, contentType: String?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let boundedData = Data(data.prefix(maximumBodyBytes))
        if let json = try? JSONSerialization.jsonObject(with: boundedData, options: [.fragmentsAllowed]) {
            var details: [String] = []
            collectMessages(in: json, depth: 0, into: &details)
            return cleaned(details.joined(separator: "; "))
        }
        guard contentType?.lowercased().hasPrefix("text/plain") == true,
              let text = String(data: boundedData, encoding: .utf8) else { return nil }
        return cleaned(text)
    }

    private static func collectMessages(in value: Any, depth: Int, into details: inout [String]) {
        guard depth < 4 else { return }
        switch value {
        case let text as String:
            if let detail = cleaned(text), !details.contains(detail) { details.append(detail) }
        case let values as [Any]:
            for value in values.prefix(5) { collectMessages(in: value, depth: depth + 1, into: &details) }
        case let fields as [String: Any]:
            // Common API error fields, including problem-details and nested error objects.
            for key in ["detail", "message", "error_description", "reason", "result", "error", "errors", "title", "code"] {
                if let value = fields[key] { collectMessages(in: value, depth: depth + 1, into: &details) }
            }
        default: break
        }
    }

    private static func cleaned(_ text: String) -> String? {
        let text = text.components(separatedBy: .controlCharacters).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty, !text.contains("<"), !text.contains(">") else { return nil }
        if text.count > maximumDetailCharacters {
            return String(text.prefix(maximumDetailCharacters - 1)) + "…"
        }
        return text
    }
}
