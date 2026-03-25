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
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "css") ?? .plainText,
        ]
    }
    
    static var writableContentTypes: [UTType] {
        readableContentTypes
    }
    
    init(text: String = "", fileType: SupportedFileType = .plainText) {
        self.text = text
        self.fileType = fileType
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
        
        // Determine file type from content type
        if let ext = configuration.contentType.preferredFilenameExtension {
            fileType = SupportedFileType.from(extension: ext)
        } else {
            fileType = .plainText
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return .init(regularFileWithContents: data)
    }
}
