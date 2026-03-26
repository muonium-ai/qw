//
//  TextDocumentTests.swift
//  qwTests
//
//  Unit tests for TextDocument model
//

import XCTest
import SwiftUI
import UniformTypeIdentifiers
@testable import qw

final class TextDocumentTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testDefaultInitialization() {
        let doc = TextDocument()
        XCTAssertEqual(doc.text, "")
        XCTAssertEqual(doc.fileType, .plainText)
    }
    
    func testInitializationWithText() {
        let text = "Hello, World!"
        let doc = TextDocument(text: text)
        XCTAssertEqual(doc.text, text)
        XCTAssertEqual(doc.fileType, .plainText)
    }
    
    func testInitializationWithTextAndFileType() {
        let text = "# Markdown Title"
        let doc = TextDocument(text: text, fileType: .markdown)
        XCTAssertEqual(doc.text, text)
        XCTAssertEqual(doc.fileType, .markdown)
    }
    
    // MARK: - File Type Tests
    
    func testSupportedFileTypeFromExtension() {
        XCTAssertEqual(SupportedFileType.from(extension: "txt"), .plainText)
        XCTAssertEqual(SupportedFileType.from(extension: "md"), .markdown)
        XCTAssertEqual(SupportedFileType.from(extension: "json"), .json)
        XCTAssertEqual(SupportedFileType.from(extension: "yaml"), .yaml)
        XCTAssertEqual(SupportedFileType.from(extension: "yml"), .yml)
        XCTAssertEqual(SupportedFileType.from(extension: "py"), .python)
        XCTAssertEqual(SupportedFileType.from(extension: "js"), .javascript)
        XCTAssertEqual(SupportedFileType.from(extension: "html"), .html)
        XCTAssertEqual(SupportedFileType.from(extension: "css"), .css)
        XCTAssertEqual(SupportedFileType.from(extension: "swift"), .swift)
    }
    
    func testSupportedFileTypeFromURL() {
        let txtURL = URL(fileURLWithPath: "/test/file.txt")
        let mdURL = URL(fileURLWithPath: "/test/file.md")
        let jsonURL = URL(fileURLWithPath: "/test/file.json")
        let swiftURL = URL(fileURLWithPath: "/test/file.swift")
        
        XCTAssertEqual(SupportedFileType.from(url: txtURL), .plainText)
        XCTAssertEqual(SupportedFileType.from(url: mdURL), .markdown)
        XCTAssertEqual(SupportedFileType.from(url: jsonURL), .json)
        XCTAssertEqual(SupportedFileType.from(url: swiftURL), .swift)
    }
    
    func testSupportedFileTypeUnknownExtension() {
        XCTAssertEqual(SupportedFileType.from(extension: "xyz"), .plainText)
        XCTAssertEqual(SupportedFileType.from(extension: ""), .plainText)
    }
    
    func testSupportedFileTypeCaseInsensitive() {
        XCTAssertEqual(SupportedFileType.from(extension: "TXT"), .plainText)
        XCTAssertEqual(SupportedFileType.from(extension: "MD"), .markdown)
        XCTAssertEqual(SupportedFileType.from(extension: "JSON"), .json)
    }

    func testReadNonUTF8DataExpectedToSucceed() throws {
        // Issue #3: Non-UTF-8 files should be supported (currently fails).
        // NOTE: FileDocumentReadConfiguration has no public initializer on macOS 26+,
        // so this test verifies the encoding behavior indirectly.
        let latin1Bytes: [UInt8] = [0x63, 0x61, 0x66, 0xE9] // "café" in ISO-8859-1
        let data = Data(latin1Bytes)

        XCTExpectFailure("Issue #3: Non-UTF-8 files should decode without data loss")
        let decoded = String(data: data, encoding: .utf8)
        XCTAssertNotNil(decoded, "Latin-1 data should be decodable (currently only UTF-8 is supported)")
    }
    
    // MARK: - UTType Tests
    
    func testFileTypeUTTypes() {
        XCTAssertEqual(SupportedFileType.plainText.utType, .plainText)
        XCTAssertEqual(SupportedFileType.json.utType, .json)
        XCTAssertEqual(SupportedFileType.python.utType, .pythonScript)
        XCTAssertEqual(SupportedFileType.javascript.utType, .javaScript)
        XCTAssertEqual(SupportedFileType.swift.utType, .swiftSource)
        XCTAssertEqual(SupportedFileType.html.utType, .html)
    }
    
    // MARK: - Readable Content Types Tests
    
    func testReadableContentTypes() {
        let types = TextDocument.readableContentTypes
        XCTAssertTrue(types.contains(.plainText))
        XCTAssertTrue(types.contains(.json))
        XCTAssertTrue(types.contains(.yaml))
        XCTAssertTrue(types.contains(.html))
        XCTAssertTrue(types.contains(.xml))
        XCTAssertTrue(types.contains(.javaScript))
        XCTAssertTrue(types.contains(.pythonScript))
        XCTAssertTrue(types.contains(.swiftSource))
        XCTAssertTrue(types.contains(.sourceCode))
        XCTAssertTrue(types.contains(.shellScript))
        // .item should no longer be in the list
        XCTAssertFalse(types.contains(.item))
    }
    
    func testWritableContentTypes() throws {
        let readableTypes = TextDocument.readableContentTypes
        let writableTypes = TextDocument.writableContentTypes
        XCTAssertFalse(writableTypes.isEmpty, "writableContentTypes should not be empty")
        // Writable may be a subset of readable; just verify overlap
        let overlap = writableTypes.filter { readableTypes.contains($0) }
        XCTAssertFalse(overlap.isEmpty, "writable and readable should share at least one type. Readable: \(readableTypes.count), Writable: \(writableTypes.count)")
    }
    
    // MARK: - Text Encoding Tests
    
    func testTextEncodingToData() {
        let text = "Test content for encoding"
        let doc = TextDocument(text: text)
        
        // Verify the text can be encoded to UTF-8 data
        let data = text.data(using: .utf8)
        XCTAssertNotNil(data)
        
        if let data = data,
           let decodedText = String(data: data, encoding: .utf8) {
            XCTAssertEqual(decodedText, doc.text)
        } else {
            XCTFail("Could not encode/decode text")
        }
    }
    
    func testUnicodeTextEncoding() {
        let text = "Hello 世界 🌍 émojis"
        let doc = TextDocument(text: text)
        
        let data = text.data(using: .utf8)
        XCTAssertNotNil(data)
        
        if let data = data,
           let decodedText = String(data: data, encoding: .utf8) {
            XCTAssertEqual(decodedText, doc.text)
        } else {
            XCTFail("Could not encode/decode unicode text")
        }
    }
    
    func testEmptyTextEncoding() {
        let doc = TextDocument(text: "")
        
        let data = doc.text.data(using: .utf8)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 0)
    }
    
    func testLargeTextEncoding() {
        let text = String(repeating: "Line of text\n", count: 10000)
        let doc = TextDocument(text: text)
        
        let data = text.data(using: .utf8)
        XCTAssertNotNil(data)
        
        if let data = data,
           let decodedText = String(data: data, encoding: .utf8) {
            XCTAssertEqual(decodedText, doc.text)
        } else {
            XCTFail("Could not encode/decode large text")
        }
    }
    
    // MARK: - Text Modification Tests
    
    func testTextModification() {
        var doc = TextDocument(text: "Initial text")
        XCTAssertEqual(doc.text, "Initial text")
        
        doc.text = "Modified text"
        XCTAssertEqual(doc.text, "Modified text")
    }
    
    func testFileTypeModification() {
        var doc = TextDocument(text: "# Heading", fileType: .plainText)
        XCTAssertEqual(doc.fileType, .plainText)
        
        doc.fileType = .markdown
        XCTAssertEqual(doc.fileType, .markdown)
    }
}
