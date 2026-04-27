import Foundation
@preconcurrency import ImageIO
import UniformTypeIdentifiers

struct ResultPreview: Sendable {
    let resultID: String
    let title: String
    let subtitle: String
    let kind: String
    let metadata: [ResultPreviewMetadata]
    let body: String
    let imageData: Data?

    init(
        resultID: String,
        title: String,
        subtitle: String,
        kind: String,
        metadata: [ResultPreviewMetadata],
        body: String,
        imageData: Data? = nil
    ) {
        self.resultID = resultID
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.metadata = metadata
        self.body = body
        self.imageData = imageData
    }
}

struct ResultPreviewMetadata: Sendable {
    let title: String
    let value: String
}

enum ResultPreviewProvider {
    static func loading(for result: SearchResult) -> ResultPreview {
        ResultPreview(
            resultID: result.id,
            title: result.title,
            subtitle: result.subtitle,
            kind: result.kind.rawValue,
            metadata: [ResultPreviewMetadata(title: "Type", value: result.kind.rawValue)],
            body: "Loading preview..."
        )
    }

    static func preview(for result: SearchResult) -> ResultPreview {
        switch result.action {
        case .openApplication(let url):
            return appPreview(result, url: url)
        case .openFile(let url), .revealFile(let url):
            return filePreview(result, url: url)
        case .openURL(let url):
            return urlPreview(result, url: url)
        case .pasteClipboard(let value), .copy(let value):
            return textPreview(result, value: value)
        case .pasteSnippet:
            return genericPreview(result, body: result.subtitle.isEmpty ? "Snippet ready to paste." : result.subtitle)
        case .askAI(let prompt):
            return genericPreview(result, body: prompt.isEmpty ? "Local AI question." : prompt)
        case .system:
            return genericPreview(result, body: result.subtitle.isEmpty ? "System action." : result.subtitle)
        }
    }

    private static func filePreview(_ result: SearchResult, url: URL) -> ResultPreview {
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .localizedTypeDescriptionKey,
            .tagNamesKey
        ])
        let isDirectory = values?.isDirectory == true
        var metadata = baseMetadata(result)
        metadata.append(ResultPreviewMetadata(title: "Path", value: url.path))
        if let type = values?.localizedTypeDescription, !type.isEmpty {
            metadata.append(ResultPreviewMetadata(title: "Kind", value: type))
        }
        if let size = values?.fileSize, !isDirectory {
            metadata.append(ResultPreviewMetadata(title: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }
        if let modified = values?.contentModificationDate {
            metadata.append(ResultPreviewMetadata(title: "Modified", value: modified.formatted(date: .abbreviated, time: .shortened)))
        }
        if let tags = values?.tagNames, !tags.isEmpty {
            metadata.append(ResultPreviewMetadata(title: "Tags", value: tags.prefix(5).joined(separator: ", ")))
        }
        let dimensions = imageDimensions(url: url)
        let thumbnailData = dimensions == nil ? nil : imageThumbnailData(url: url, maxPixelSize: 520)
        if let dimensions {
            metadata.append(ResultPreviewMetadata(title: "Image", value: dimensions))
        }

        let body: String
        if isDirectory {
            body = "Folder. Press Return to open, Tab for actions, or Command-B to add it to the buffer."
        } else if thumbnailData != nil {
            body = "Image preview. Press Command-Y for Quick Look."
        } else {
            switch FilePreviewReader.preview(for: url, byteLimit: 4_096, maxCharacters: 1_200, pdfPageLimit: 1) {
            case .available(let text):
                body = text
            case .unavailable(let reason):
                body = "Preview unavailable: \(reason). Use Command-Y for Quick Look."
            }
        }

        return ResultPreview(
            resultID: result.id,
            title: result.title,
            subtitle: result.subtitle.isEmpty ? url.deletingLastPathComponent().path : result.subtitle,
            kind: result.kind.rawValue,
            metadata: metadata,
            body: body,
            imageData: thumbnailData
        )
    }

    private static func appPreview(_ result: SearchResult, url: URL) -> ResultPreview {
        var metadata = baseMetadata(result)
        metadata.append(ResultPreviewMetadata(title: "Path", value: url.path))
        if let bundle = Bundle(url: url) {
            if let id = bundle.bundleIdentifier {
                metadata.append(ResultPreviewMetadata(title: "Bundle", value: id))
            }
            if let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
                metadata.append(ResultPreviewMetadata(title: "Version", value: version))
            }
        }
        return ResultPreview(
            resultID: result.id,
            title: result.title,
            subtitle: result.subtitle.isEmpty ? "Open application" : result.subtitle,
            kind: result.kind.rawValue,
            metadata: metadata,
            body: "Press Return to open. Press Tab for actions such as reveal, copy path, or Ask AI."
        )
    }

    private static func urlPreview(_ result: SearchResult, url: URL) -> ResultPreview {
        var metadata = baseMetadata(result)
        if let host = url.host {
            metadata.append(ResultPreviewMetadata(title: "Domain", value: host))
        }
        metadata.append(ResultPreviewMetadata(title: "URL", value: url.absoluteString))
        return ResultPreview(
            resultID: result.id,
            title: result.title,
            subtitle: result.subtitle.isEmpty ? url.absoluteString : result.subtitle,
            kind: result.kind.rawValue,
            metadata: metadata,
            body: "Press Return to open. Press Tab for copy, web search, snippet, and AI actions."
        )
    }

    private static func textPreview(_ result: SearchResult, value: String) -> ResultPreview {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var metadata = baseMetadata(result)
        metadata.append(ResultPreviewMetadata(title: "Characters", value: "\(text.count)"))
        return ResultPreview(
            resultID: result.id,
            title: result.title,
            subtitle: result.subtitle,
            kind: result.kind.rawValue,
            metadata: metadata,
            body: String(text.prefix(1_200))
        )
    }

    private static func genericPreview(_ result: SearchResult, body: String) -> ResultPreview {
        ResultPreview(
            resultID: result.id,
            title: result.title,
            subtitle: result.subtitle,
            kind: result.kind.rawValue,
            metadata: baseMetadata(result),
            body: String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_200))
        )
    }

    private static func baseMetadata(_ result: SearchResult) -> [ResultPreviewMetadata] {
        [
            ResultPreviewMetadata(title: "Type", value: result.kind.rawValue),
            ResultPreviewMetadata(title: "Action", value: actionName(result.action))
        ]
    }

    private static func actionName(_ action: ResultAction) -> String {
        switch action {
        case .askAI:
            return "Ask AI"
        case .copy:
            return "Copy"
        case .openApplication:
            return "Open app"
        case .openFile:
            return "Open file"
        case .openURL:
            return "Open URL"
        case .pasteClipboard:
            return "Paste clipboard"
        case .pasteSnippet:
            return "Paste snippet"
        case .revealFile:
            return "Reveal"
        case .system:
            return "Run"
        }
    }

    private static func imageDimensions(url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return "\(width) x \(height)"
    }

    private static func imageThumbnailData(url: URL, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
