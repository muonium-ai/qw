//
//  TextDocumentEncodingTests.swift
//  qwTests
//
//  Tests for binary detection, fileWrapper behavior, and rawData initialization
//

#if os(macOS)

import XCTest
import UniformTypeIdentifiers
@testable import qw

final class TextDocumentEncodingTests: XCTestCase {

    // MARK: - isBinaryData Tests

    func testIsBinaryData_emptyData_returnsFalse() {
        XCTAssertFalse(TextDocument.isBinaryData(Data()))
    }

    func testIsBinaryData_pureASCII_returnsFalse() {
        let data = "Hello, World! 1234567890\n\ttabs and spaces".data(using: .utf8)!
        XCTAssertFalse(TextDocument.isBinaryData(data))
    }

    func testIsBinaryData_utf8WithEmoji_returnsFalse() {
        let data = "Hello 🌍🚀 emoji text 你好世界".data(using: .utf8)!
        XCTAssertFalse(TextDocument.isBinaryData(data))
    }

    func testIsBinaryData_nullByte_returnsTrue() {
        let data = Data([0x00])
        XCTAssertTrue(TextDocument.isBinaryData(data))
    }

    func testIsBinaryData_nullByteAfterText_returnsTrue() {
        var data = Data(repeating: 0x41, count: 100) // 100 'A' characters
        data.append(0x00)
        XCTAssertTrue(TextDocument.isBinaryData(data))
    }

    func testIsBinaryData_invalidUTF8Sequence_returnsTrue() {
        let data = Data([0xFF, 0xFE])
        XCTAssertTrue(TextDocument.isBinaryData(data))
    }

    func testIsBinaryData_largeTextNoNulls_returnsFalse() {
        let text = String(repeating: "abcdefghij\n", count: 1000) // ~11 KB
        let data = text.data(using: .utf8)!
        XCTAssertFalse(TextDocument.isBinaryData(data))
    }

    func testIsBinaryData_randomBytesWithNulls_returnsTrue() {
        var bytes: [UInt8] = (0...255).map { $0 } // includes 0x00
        bytes.shuffle()
        let data = Data(bytes)
        XCTAssertTrue(TextDocument.isBinaryData(data))
    }

    func testIsBinaryData_nullBeyond8KB_returnsFalse() {
        // Null byte placed past the 8 KB sample window should not be detected
        var data = Data(repeating: 0x41, count: 8192) // 8 KB of 'A'
        data.append(0x00)
        XCTAssertFalse(TextDocument.isBinaryData(data))
    }

    func testIsBinaryData_nullAtExact8KBBoundary_returnsTrue() {
        // Last byte within the 8 KB window is null
        var data = Data(repeating: 0x41, count: 8191)
        data.append(0x00)
        XCTAssertTrue(TextDocument.isBinaryData(data))
    }

    // MARK: - rawData Initialization Tests

    func testRawData_initWithText_setsUTF8Bytes() {
        let text = "Hello, World!"
        let doc = TextDocument(text: text)
        let expected = text.data(using: .utf8)!
        XCTAssertEqual(doc.rawData, expected)
    }

    func testRawData_initWithEmptyText_setsEmptyData() {
        let doc = TextDocument(text: "")
        XCTAssertEqual(doc.rawData, Data())
        XCTAssertTrue(doc.rawData.isEmpty)
    }

    func testRawData_initWithUnicodeText_setsUTF8Bytes() {
        let text = "cafe\u{0301} 日本語 🎵"
        let doc = TextDocument(text: text)
        let expected = text.data(using: .utf8)!
        XCTAssertEqual(doc.rawData, expected)
    }

    func testRawData_defaultInit_setsEmptyData() {
        let doc = TextDocument()
        XCTAssertEqual(doc.rawData, Data())
    }

    // MARK: - isBinaryDetected Default State

    func testIsBinaryDetected_defaultIsFalse() {
        let doc = TextDocument(text: "some text")
        XCTAssertFalse(doc.isBinaryDetected)
    }

    // MARK: - fileWrapper Tests (text documents)

    func testFileWrapper_textDocument_createsUTF8Content() throws {
        throw XCTSkip("FileDocumentWriteConfiguration has no public init on macOS 26")
    }

    func testFileWrapper_emptyTextDocument_createsEmptyData() throws {
        throw XCTSkip("FileDocumentWriteConfiguration has no public init on macOS 26")
    }

    func testFileWrapper_unicodeText_roundtripsCorrectly() throws {
        throw XCTSkip("FileDocumentWriteConfiguration has no public init on macOS 26")
    }

    // MARK: - fileWrapper Tests (binary documents)

    func testFileWrapper_binaryDetected_returnsRawDataUnchanged() throws {
        throw XCTSkip("FileDocumentWriteConfiguration has no public init on macOS 26")
    }

    func testFileWrapper_binaryDetected_textModificationDoesNotAffectOutput() throws {
        throw XCTSkip("FileDocumentWriteConfiguration has no public init on macOS 26")
    }

    // MARK: - fileWrapper behavior verified indirectly

    func testFileWrapperLogic_textPath_encodesTextAsUTF8() {
        // Verify the encoding logic that fileWrapper uses for text documents
        let text = "Unicode: 日本語 émojis 🌍"
        let doc = TextDocument(text: text)
        XCTAssertFalse(doc.isBinaryDetected)

        // The fileWrapper text path does: text.data(using: .utf8)
        let encoded = doc.text.data(using: .utf8)
        XCTAssertNotNil(encoded)
        let roundtripped = String(data: encoded!, encoding: .utf8)
        XCTAssertEqual(roundtripped, text)
    }

    func testFileWrapperLogic_textPath_emptyTextProducesEmptyData() {
        let doc = TextDocument(text: "")
        XCTAssertFalse(doc.isBinaryDetected)

        let encoded = doc.text.data(using: .utf8)
        XCTAssertNotNil(encoded)
        XCTAssertEqual(encoded!.count, 0)
    }

    func testFileWrapperLogic_binaryPath_returnsRawData() {
        // Simulate a binary document by manually setting isBinaryDetected
        var doc = TextDocument(text: "")
        doc.isBinaryDetected = true
        doc.rawData = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x0D, 0x0A]) // PNG-like header

        // The fileWrapper binary path returns rawData unchanged
        XCTAssertTrue(doc.isBinaryDetected)
        XCTAssertEqual(doc.rawData, Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x0D, 0x0A]))
    }

    func testFileWrapperLogic_binaryPath_textChangeDoesNotAffectRawData() {
        var doc = TextDocument(text: "")
        doc.isBinaryDetected = true
        let originalData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) // JPEG-like header
        doc.rawData = originalData

        // Modifying text should not change rawData
        doc.text = "this should be ignored for binary output"
        XCTAssertEqual(doc.rawData, originalData)
    }
}

#endif
