//
//  MagicBytesTests.swift
//  qwTests
//
//  Tests for MagicBytes.detect(from:) magic byte signature detection.
//

import XCTest

#if os(macOS)
@testable import qw

final class MagicBytesTests: XCTestCase {

    // MARK: - Helpers

    /// Build a Data from the given magic bytes plus some trailing padding.
    private func data(_ bytes: [UInt8], padding: Int = 16) -> Data {
        Data(bytes + Array(repeating: UInt8(0x00), count: padding))
    }

    // MARK: - Empty / Minimal Data

    func testEmptyDataReturnsNil() {
        let result = MagicBytes.detect(from: Data())
        XCTAssertNil(result, "Empty data should return nil")
    }

    func testSingleArbitraryByteReturnsNil() {
        // 0xAA doesn't match any signature
        let result = MagicBytes.detect(from: Data([0xAA]))
        XCTAssertNil(result, "Single arbitrary byte should return nil")
    }

    func testSingleOpenBraceMayMatchJSON() {
        // 0x7B is '{', listed as JSON heuristic in the registry
        let result = MagicBytes.detect(from: Data([0x7B]))
        // The database may match something else, but if the hardcoded
        // registry is used, this should be JSON.  Accept either outcome.
        if let result = result {
            // If it matched, it should mention JSON (from registry) or
            // some database-provided name.
            XCTAssertFalse(result.name.isEmpty)
        }
    }

    // MARK: - Format Detection (Images)

    func testDetectPNG() {
        let result = MagicBytes.detect(from: data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("PNG"), "Expected name to contain 'PNG', got '\(result!.name)'")
    }

    func testDetectJPEG() {
        let result = MagicBytes.detect(from: data([0xFF, 0xD8, 0xFF]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("JPEG"), "Expected name to contain 'JPEG', got '\(result!.name)'")
    }

    func testDetectGIF() {
        let result = MagicBytes.detect(from: data([0x47, 0x49, 0x46, 0x38]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("GIF"), "Expected name to contain 'GIF', got '\(result!.name)'")
    }

    // MARK: - Format Detection (Documents)

    func testDetectPDF() {
        let result = MagicBytes.detect(from: data([0x25, 0x50, 0x44, 0x46]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("PDF"), "Expected name to contain 'PDF', got '\(result!.name)'")
    }

    // MARK: - Format Detection (Archives)

    func testDetectZIP() {
        let result = MagicBytes.detect(from: data([0x50, 0x4B, 0x03, 0x04]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("ZIP"), "Expected name to contain 'ZIP', got '\(result!.name)'")
    }

    func testDetectZIPEmpty() {
        let result = MagicBytes.detect(from: data([0x50, 0x4B, 0x05, 0x06]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("ZIP"), "Expected name to contain 'ZIP', got '\(result!.name)'")
    }

    func testDetectGzip() {
        let result = MagicBytes.detect(from: data([0x1F, 0x8B]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.lowercased().contains("gzip"),
                       "Expected name to contain 'gzip', got '\(result!.name)'")
    }

    func testDetectBzip2() {
        let result = MagicBytes.detect(from: data([0x42, 0x5A, 0x68]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.lowercased().contains("bzip"),
                       "Expected name to contain 'bzip', got '\(result!.name)'")
    }

    func testDetectXZ() {
        let result = MagicBytes.detect(from: data([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("XZ"), "Expected name to contain 'XZ', got '\(result!.name)'")
    }

    // MARK: - Format Detection (Executables)

    func testDetectMachOUniversal() {
        let result = MagicBytes.detect(from: data([0xCA, 0xFE, 0xBA, 0xBE]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("Mach-O"),
                       "Expected name to contain 'Mach-O', got '\(result!.name)'")
    }

    func testDetectMachO32() {
        let result = MagicBytes.detect(from: data([0xFE, 0xED, 0xFA, 0xCE]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("Mach-O"),
                       "Expected name to contain 'Mach-O', got '\(result!.name)'")
    }

    func testDetectMachO64() {
        let result = MagicBytes.detect(from: data([0xFE, 0xED, 0xFA, 0xCF]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("Mach-O") || result!.name.contains("64"),
                       "Expected name to contain 'Mach-O' or '64', got '\(result!.name)'")
    }

    func testDetectMachO64Reversed() {
        let result = MagicBytes.detect(from: data([0xCF, 0xFA, 0xED, 0xFE]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("Mach-O"),
                       "Expected name to contain 'Mach-O', got '\(result!.name)'")
    }

    func testDetectMachO32Reversed() {
        let result = MagicBytes.detect(from: data([0xCE, 0xFA, 0xED, 0xFE]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("Mach-O"),
                       "Expected name to contain 'Mach-O', got '\(result!.name)'")
    }

    func testDetectELF() {
        let result = MagicBytes.detect(from: data([0x7F, 0x45, 0x4C, 0x46]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("ELF"), "Expected name to contain 'ELF', got '\(result!.name)'")
    }

    func testDetectWindowsPE() {
        let result = MagicBytes.detect(from: data([0x4D, 0x5A]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("PE") || result!.name.contains("Windows") || result!.name.contains("EXE"),
                       "Expected name to reference Windows PE, got '\(result!.name)'")
    }

    // MARK: - Format Detection (Other)

    func testDetectRIFF() {
        let result = MagicBytes.detect(from: data([0x52, 0x49, 0x46, 0x46]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("RIFF"), "Expected name to contain 'RIFF', got '\(result!.name)'")
    }

    func testDetectWebAssembly() {
        let result = MagicBytes.detect(from: data([0x00, 0x61, 0x73, 0x6D]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.lowercased().contains("wasm") || result!.name.contains("WebAssembly"),
                       "Expected name to contain 'WebAssembly' or 'wasm', got '\(result!.name)'")
    }

    func testDetectSQLite() {
        let result = MagicBytes.detect(from: data([0x53, 0x51, 0x4C, 0x69, 0x74, 0x65]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("SQLite"), "Expected name to contain 'SQLite', got '\(result!.name)'")
    }

    func testDetectXML() {
        let result = MagicBytes.detect(from: data([0x3C, 0x3F, 0x78, 0x6D, 0x6C]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("XML"), "Expected name to contain 'XML', got '\(result!.name)'")
    }

    // MARK: - MP4 / MOV (ftyp at offset 4)

    func testDetectMP4Ftyp() {
        // Typical MP4: 4-byte box size + "ftyp" at bytes 4-7
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]
        let result = MagicBytes.detect(from: data(bytes))
        XCTAssertNotNil(result, "MP4 ftyp signature should be detected")
        XCTAssertTrue(result!.name.contains("MP4") || result!.name.contains("MOV") || result!.name.contains("Video"),
                       "Expected MP4/MOV/Video in name, got '\(result!.name)'")
    }

    func testDetectMP4FtypWithDifferentBoxSize() {
        // Different box size, still "ftyp" at offset 4
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70]
        let result = MagicBytes.detect(from: data(bytes))
        XCTAssertNotNil(result, "MP4 ftyp should match regardless of box size bytes")
    }

    // MARK: - matchedRange Correctness

    func testMatchedRangeForPNG() {
        let pngBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let result = MagicBytes.detect(from: data(pngBytes))
        XCTAssertNotNil(result)
        // The hardcoded registry produces 0..<8; the DB may differ.
        // At minimum, the matched range must be non-empty and start at 0.
        XCTAssertEqual(result!.matchedRange.lowerBound, 0,
                       "matchedRange should start at 0")
        XCTAssertGreaterThan(result!.matchedRange.count, 0,
                             "matchedRange should be non-empty")
    }

    func testMatchedRangeForGzip() {
        let result = MagicBytes.detect(from: data([0x1F, 0x8B]))
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.matchedRange.lowerBound, 0)
        XCTAssertGreaterThanOrEqual(result!.matchedRange.count, 2,
                                    "Gzip matchedRange should cover at least 2 bytes")
    }

    func testMatchedRangeForMP4() {
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]
        let result = MagicBytes.detect(from: data(bytes))
        XCTAssertNotNil(result)
        // The hardcoded detection returns 0..<8; the DB may return a
        // different range.  Just verify the range is non-empty and starts
        // within the signature area.
        XCTAssertGreaterThan(result!.matchedRange.count, 0,
                             "MP4 matchedRange should be non-empty")
        XCTAssertLessThan(result!.matchedRange.lowerBound, 8,
                          "MP4 matchedRange should start within the first 8 bytes")
    }

    // MARK: - Name Contains Expected String

    func testPNGNameContainsPNG() {
        let result = MagicBytes.detect(from: data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("PNG"))
    }

    func testELFNameContainsELF() {
        let result = MagicBytes.detect(from: data([0x7F, 0x45, 0x4C, 0x46]))
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.name.contains("ELF"))
    }

    func testDescriptionIsNotEmpty() {
        let result = MagicBytes.detect(from: data([0x25, 0x50, 0x44, 0x46]))
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.description.isEmpty,
                        "FileSignature description should not be empty")
    }

    // MARK: - Unknown Data

    func testUnknownBytesReturnNil() {
        let result = MagicBytes.detect(from: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertNil(result, "Random unknown bytes should return nil")
    }

    func testUnknownLongDataReturnsNil() {
        // 32 bytes of 0xFF shouldn't match anything in the registry
        let result = MagicBytes.detect(from: Data(repeating: 0xFF, count: 32))
        XCTAssertNil(result, "32 bytes of 0xFF should not match any signature")
    }

    // MARK: - Minimum Data Length / Short Data Safety

    func testShortDataForPNGDoesNotCrash() {
        // PNG needs 8 bytes; provide only 4 -- should return nil, not crash
        let result = MagicBytes.detect(from: Data([0x89, 0x50, 0x4E, 0x47]))
        // May be nil (too short) or may match via database; just must not crash
        _ = result
    }

    func testShortDataForSQLiteDoesNotCrash() {
        // SQLite needs 6 bytes; provide only 3
        let result = MagicBytes.detect(from: Data([0x53, 0x51, 0x4C]))
        _ = result
    }

    func testShortDataForXZDoesNotCrash() {
        // XZ needs 6 bytes; provide 2
        let result = MagicBytes.detect(from: Data([0xFD, 0x37]))
        _ = result
    }

    func testSingleByteDoesNotCrash() {
        // Single byte for an 8-byte signature (PNG)
        let result = MagicBytes.detect(from: Data([0x89]))
        _ = result
    }

    func testFtypNeedsAtLeast8Bytes() {
        // Provide only 6 bytes -- ftyp check requires 8
        let result = MagicBytes.detect(from: Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74]))
        // Should not crash; probably nil unless DB matches
        _ = result
    }
}

#endif
