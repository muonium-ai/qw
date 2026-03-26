//
//  TextDocument.swift
//  qw
//
//  A text document model for QW editor
//

import SwiftUI
import UniformTypeIdentifiers

/// Supported file types for the QW editor
enum SupportedFileType: String, CaseIterable {
    case plainText = "txt"
    case markdown = "md"
    case json = "json"
    case yaml = "yaml"
    case yml = "yml"
    case python = "py"
    case javascript = "js"
    case html = "html"
    case css = "css"
    case swift = "swift"
    
    var utType: UTType {
        switch self {
        case .plainText: return .plainText
        case .markdown: return .init(filenameExtension: "md") ?? .plainText
        case .json: return .json
        case .yaml, .yml: return .yaml
        case .python: return .pythonScript
        case .javascript: return .javaScript
        case .html: return .html
        case .css: return .init(filenameExtension: "css") ?? .plainText
        case .swift: return .swiftSource
        }
    }
    
    static func from(extension ext: String) -> SupportedFileType {
        return SupportedFileType(rawValue: ext.lowercased()) ?? .plainText
    }
    
    static func from(url: URL) -> SupportedFileType {
        return from(extension: url.pathExtension)
    }
}

/// The main text document structure
struct TextDocument: FileDocument {
    var text: String
    var fileType: SupportedFileType
    /// Raw file bytes, kept for hex viewing (especially useful for binary files).
    var rawData: Data
    /// Whether binary content was detected when opening the file.
    var isBinaryDetected: Bool = false

    static var readableContentTypes: [UTType] {
        [
            .plainText,
            .json,
            .yaml,
            .html,
            .xml,
            .javaScript,
            .pythonScript,
            .swiftSource,
            .sourceCode,
            .shellScript,
            .data,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "css") ?? .plainText,
        ]
    }

    static var writableContentTypes: [UTType] {
        // Exclude .data from writable types — we don't write binary files as text
        readableContentTypes.filter { $0 != .data }
    }

    /// Checks the first 8 KB of data for null bytes or invalid UTF-8,
    /// which indicates the file is likely binary.
    static func isBinaryData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let sampleSize = min(data.count, 8192)
        let sample = data.prefix(sampleSize)

        // Check for null bytes — strong binary indicator
        if sample.contains(0x00) {
            return true
        }

        // Check if the sample is valid UTF-8
        if String(data: Data(sample), encoding: .utf8) == nil {
            return true
        }

        return false
    }

    init(text: String = "", fileType: SupportedFileType = .plainText) {
        self.text = text
        self.fileType = fileType
        self.rawData = text.data(using: .utf8) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        rawData = data

        // Determine file type from content type
        if let ext = configuration.contentType.preferredFilenameExtension {
            fileType = SupportedFileType.from(extension: ext)
        } else {
            fileType = .plainText
        }

        // If binary, store data but use a placeholder for text
        if TextDocument.isBinaryData(data) {
            isBinaryDetected = true
            text = ""
        } else if let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            // Fallback: treat as binary
            isBinaryDetected = true
            text = ""
        }
    }

    /// Shared write path used by FileDocument conformance and tests.
    func makeFileWrapper() -> FileWrapper {
        if isBinaryDetected {
            // Write back the original raw data for binary files
            return .init(regularFileWithContents: rawData)
        }
        let data = text.data(using: .utf8) ?? Data()
        return .init(regularFileWithContents: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        makeFileWrapper()
    }
}
