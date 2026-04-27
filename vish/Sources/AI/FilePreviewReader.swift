import Foundation
@preconcurrency import PDFKit

enum TinyFilePreview: Sendable {
    case available(String)
    case unavailable(String)
}

enum FilePreviewReader {
    static func preview(
        for url: URL,
        byteLimit: Int = 8_192,
        maxCharacters: Int = 6_000,
        pdfPageLimit: Int = 3
    ) -> TinyFilePreview {
        guard !isSensitive(url) else { return .unavailable("sensitive path denied") }
        if url.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame {
            return pdfPreview(url, pageLimit: pdfPageLimit, maxCharacters: maxCharacters)
        }
        return textPreview(url, byteLimit: byteLimit, maxCharacters: maxCharacters)
    }

    private static func pdfPreview(_ url: URL, pageLimit: Int, maxCharacters: Int) -> TinyFilePreview {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 128_000_000 {
            return .unavailable("file too large for quick preview")
        }
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            return .unavailable("PDF text unavailable")
        }

        var output = ""
        for index in 0..<min(document.pageCount, pageLimit) {
            guard let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                continue
            }
            if !output.isEmpty { output.append("\n") }
            output.append(text)
            if output.count >= maxCharacters { break }
        }
        let clipped = clipped(output, maxCharacters: maxCharacters)
        return clipped.isEmpty ? .unavailable("PDF has no extractable text in preview pages") : .available(clipped)
    }

    private static func textPreview(_ url: URL, byteLimit: Int, maxCharacters: Int) -> TinyFilePreview {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unavailable("cannot read file") }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: byteLimit)) ?? Data()
        guard !data.isEmpty else { return .unavailable("empty file") }
        guard !data.contains(0) else { return .unavailable("binary content") }
        guard let text = String(data: data, encoding: .utf8) else { return .unavailable("not UTF-8 text") }
        guard looksTextual(text) else { return .unavailable("non-text content") }
        return .available(clipped(text, maxCharacters: maxCharacters))
    }

    private static func isSensitive(_ url: URL) -> Bool {
        let lower = url.path.lowercased()
        let denied = [
            "/.ssh/",
            "/.gnupg/",
            "/keychain",
            "1password",
            "bitwarden",
            ".env",
            "id_rsa",
            "id_ed25519",
            ".pem",
            ".p12",
            ".key"
        ]
        return denied.contains { lower.contains($0) }
    }

    private static func looksTextual(_ value: String) -> Bool {
        let sample = value.prefix(1_024)
        guard !sample.isEmpty else { return false }
        let controlCount = sample.unicodeScalars.filter {
            $0.value < 32 && $0.value != 10 && $0.value != 13 && $0.value != 9
        }.count
        return Double(controlCount) / Double(sample.count) < 0.05
    }

    private static func clipped(_ value: String, maxCharacters: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        return "\(trimmed.prefix(maxCharacters))\n...[truncated]"
    }
}
