//
//  FormatMismatchDetectorTests.swift
//  qwTests
//
//  Tests for FormatMismatchDetector: extension vs magic-bytes mismatch detection.
//

import XCTest

#if os(macOS)
@testable import qw

final class FormatMismatchDetectorTests: XCTestCase {

    // MARK: - Helper

    private func url(withExtension ext: String) -> URL {
        URL(fileURLWithPath: "/tmp/testfile.\(ext)")
    }

    // MARK: - isExecutableFormat

    func testIsExecutableFormat_machO() {
        XCTAssertTrue(FormatMismatchDetector.isExecutableFormat(name: "Mach-O 64-bit executable"))
    }

    func testIsExecutableFormat_elf() {
        XCTAssertTrue(FormatMismatchDetector.isExecutableFormat(name: "ELF 64-bit LSB executable"))
    }

    func testIsExecutableFormat_windowsPE() {
        XCTAssertTrue(FormatMismatchDetector.isExecutableFormat(name: "Windows PE executable"))
    }

    func testIsExecutableFormat_webAssembly() {
        XCTAssertTrue(FormatMismatchDetector.isExecutableFormat(name: "WebAssembly binary"))
    }

    func testIsExecutableFormat_pngImage_returnsFalse() {
        XCTAssertFalse(FormatMismatchDetector.isExecutableFormat(name: "PNG Image"))
    }

    func testIsExecutableFormat_pdf_returnsFalse() {
        XCTAssertFalse(FormatMismatchDetector.isExecutableFormat(name: "PDF Document"))
    }

    // MARK: - check() returns nil (no mismatch)

    func testCheck_nilFileURL_returnsNil() {
        let result = FormatMismatchDetector.check(fileURL: nil, detectedFormatName: "PNG Image", detectedCategory: "image")
        XCTAssertNil(result)
    }

    func testCheck_noExtension_returnsNil() {
        let noExtURL = URL(fileURLWithPath: "/tmp/testfile")
        let result = FormatMismatchDetector.check(fileURL: noExtURL, detectedFormatName: "PNG Image", detectedCategory: "image")
        XCTAssertNil(result)
    }

    func testCheck_nilFormatName_returnsNil() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "png"), detectedFormatName: nil, detectedCategory: "image")
        XCTAssertNil(result)
    }

    func testCheck_emptyFormatName_returnsNil() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "png"), detectedFormatName: "", detectedCategory: "image")
        XCTAssertNil(result)
    }

    func testCheck_unknownExtension_returnsNil() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "xyz"), detectedFormatName: "PNG Image", detectedCategory: "image")
        XCTAssertNil(result)
    }

    func testCheck_matchingCategories_returnsNil() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "png"), detectedFormatName: "PNG Image", detectedCategory: "image")
        XCTAssertNil(result)
    }

    func testCheck_proprietaryCategory_alwaysMatches() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "png"), detectedFormatName: "Photoshop PSD", detectedCategory: "proprietary")
        XCTAssertNil(result)
    }

    func testCheck_3dOpenCategory_alwaysMatches() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "jpg"), detectedFormatName: "glTF Binary", detectedCategory: "3d-open")
        XCTAssertNil(result)
    }

    // MARK: - CRITICAL security: executable content disguised with non-executable extension

    func testCheck_jpgWithMachO_returnsCritical() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "jpg"), detectedFormatName: "Mach-O 64-bit executable", detectedCategory: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .critical)
        XCTAssertEqual(result?.extensionType, "image")
        XCTAssertEqual(result?.detectedType, "executable")
    }

    func testCheck_pngWithELF_returnsCritical() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "png"), detectedFormatName: "ELF 64-bit LSB executable", detectedCategory: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .critical)
    }

    func testCheck_pdfWithWindowsPE_returnsCritical() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "pdf"), detectedFormatName: "Windows PE executable", detectedCategory: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .critical)
    }

    func testCheck_mp3WithWebAssembly_returnsCritical() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "mp3"), detectedFormatName: "WebAssembly binary", detectedCategory: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .critical)
    }

    func testCheck_criticalMismatch_messageContainsSecurityWarning() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "jpg"), detectedFormatName: "Mach-O 64-bit executable", detectedCategory: nil)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.message.contains("SECURITY WARNING") ?? false, "Critical mismatch message should contain 'SECURITY WARNING'")
    }

    // MARK: - Warning: mismatched categories (non-executable)

    func testCheck_exeWithPNGContent_returnsWarning() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "exe"), detectedFormatName: "PNG Image", detectedCategory: "image")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .warning)
        XCTAssertEqual(result?.extensionType, "executable")
        XCTAssertEqual(result?.detectedType, "image")
    }

    func testCheck_jpgWithPDFContent_returnsWarning() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "jpg"), detectedFormatName: "PDF Document", detectedCategory: "document")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .warning)
        XCTAssertEqual(result?.extensionType, "image")
        XCTAssertEqual(result?.detectedType, "document")
    }

    // MARK: - Info: uncategorizable format name

    func testCheck_knownExtension_uncategorizableFormat_returnsInfo() {
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "jpg"), detectedFormatName: "SomeObscureFormat", detectedCategory: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .info)
        XCTAssertEqual(result?.extensionType, "image")
        XCTAssertEqual(result?.detectedType, "unknown")
    }

    // MARK: - DB category takes precedence over inferred category

    func testCheck_dbCategoryOverridesInferredCategory() {
        // Format name "PNG Image" would infer "image", but DB says "document".
        // Extension is .mp3 (audio), so there should be a mismatch with the DB category.
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "mp3"), detectedFormatName: "PNG Image", detectedCategory: "document")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .warning)
        XCTAssertEqual(result?.detectedType, "document", "Should use DB category 'document', not inferred 'image'")
    }

    func testCheck_dbCategoryMatches_returnsNil() {
        // Format name "SomeObscureFormat" can't be inferred, but DB says "image" which matches .png.
        let result = FormatMismatchDetector.check(fileURL: url(withExtension: "png"), detectedFormatName: "SomeObscureFormat", detectedCategory: "image")
        XCTAssertNil(result, "DB category 'image' matches .png extension, so no mismatch")
    }

    // MARK: - Severity ordering

    func testSeverity_criticalIsHighest() {
        // Comparable conformance: critical < warning < info (lower raw = higher priority)
        XCTAssertTrue(FormatMismatchDetector.Severity.critical < FormatMismatchDetector.Severity.warning)
        XCTAssertTrue(FormatMismatchDetector.Severity.warning < FormatMismatchDetector.Severity.info)
    }
}

#endif
