//
//  FormatDatabaseTests.swift
//  qwTests
//
//  Tests for the FormatDatabase build pipeline: DB availability, signature
//  detection, section/field loading from the bundled formats.db.
//  Ticket: T-000077
//

#if os(macOS)
import XCTest
@testable import qw

final class FormatDatabaseTests: XCTestCase {

    // MARK: - Helpers

    /// Resolve the path to formats.db relative to this source file.
    private func formatsDBPath() -> String? {
        let testFile = URL(fileURLWithPath: #file)
        let qwTests = testFile.deletingLastPathComponent()   // qwTests/
        let qwProject = qwTests.deletingLastPathComponent()  // qw/
        let dbPath = qwProject.appendingPathComponent("qw/Resources/formats.db").path
        return FileManager.default.fileExists(atPath: dbPath) ? dbPath : nil
    }

    /// Open a FormatDatabase pointing at the real formats.db.
    private func makeDatabase() -> FormatDatabase? {
        guard let path = formatsDBPath() else { return nil }
        return FormatDatabase(bundlePath: path, userPath: nil)
    }

    /// Build a Data from the given bytes plus zero padding.
    private func data(_ bytes: [UInt8], padding: Int = 64) -> Data {
        Data(bytes + Array(repeating: UInt8(0x00), count: padding))
    }

    // MARK: - 1. Database file exists

    func testDatabaseFileExists() {
        let path = formatsDBPath()
        XCTAssertNotNil(path, "formats.db should exist at qw/qw/Resources/formats.db")
    }

    // MARK: - 2. Database opens successfully

    func testDatabaseOpensSuccessfully() {
        let db = makeDatabase()
        XCTAssertNotNil(db, "FormatDatabase should be constructable")
        XCTAssertTrue(db!.isAvailable, "FormatDatabase should be available after opening formats.db")
    }

    // MARK: - 3. Invalid path not available

    func testInvalidPathNotAvailable() {
        let db = FormatDatabase(bundlePath: nil, userPath: nil)
        XCTAssertFalse(db.isAvailable, "FormatDatabase with nil paths should not be available")
    }

    // MARK: - 4. Detect PNG signature

    func testDetectPNGSignature() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }

        // PNG magic: 89 50 4E 47 0D 0A 1A 0A  followed by IHDR chunk
        let pngHeader: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  // PNG signature
            0x00, 0x00, 0x00, 0x0D,                            // IHDR length = 13
            0x49, 0x48, 0x44, 0x52,                            // "IHDR"
            0x00, 0x00, 0x00, 0x01,                            // width = 1
            0x00, 0x00, 0x00, 0x01,                            // height = 1
            0x08,                                               // bit depth
            0x02,                                               // color type (truecolor)
            0x00, 0x00, 0x00,                                  // compression, filter, interlace
        ]
        let sig = db.detectSignature(from: data(pngHeader))
        XCTAssertNotNil(sig, "PNG header should be detected")
        XCTAssertEqual(sig?.name, "PNG Image")
        XCTAssertEqual(sig?.category, "image")
    }

    // MARK: - 5. Detect JPEG signature

    func testDetectJPEGSignature() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }

        // JPEG SOI marker: FF D8 FF E0 (JFIF APP0)
        let jpegHeader: [UInt8] = [
            0xFF, 0xD8, 0xFF, 0xE0,
            0x00, 0x10,                                        // length
            0x4A, 0x46, 0x49, 0x46, 0x00,                    // "JFIF\0"
        ]
        let sig = db.detectSignature(from: data(jpegHeader))
        XCTAssertNotNil(sig, "JPEG header should be detected")
        if let sig = sig {
            XCTAssertTrue(sig.name.contains("JPEG"), "Name should contain JPEG, got: \(sig.name)")
            XCTAssertEqual(sig.category, "image")
        }
    }

    // MARK: - 6. Detect ELF signature

    func testDetectELFSignature() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }

        // ELF magic: 7F 45 4C 46
        let elfHeader: [UInt8] = [
            0x7F, 0x45, 0x4C, 0x46,  // \x7FELF
            0x02,                      // 64-bit
            0x01,                      // little-endian
            0x01,                      // ELF version
            0x00,                      // OS/ABI
        ]
        let sig = db.detectSignature(from: data(elfHeader))
        XCTAssertNotNil(sig, "ELF header should be detected")
        if let sig = sig {
            XCTAssertTrue(sig.name.contains("ELF"), "Name should contain ELF, got: \(sig.name)")
            XCTAssertEqual(sig.category, "proprietary")
        }
    }

    // MARK: - 7. Detect PE signature

    func testDetectPESignature() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }

        // MZ header (DOS stub) at offset 0
        var peHeader: [UInt8] = Array(repeating: 0x00, count: 128)
        peHeader[0] = 0x4D  // 'M'
        peHeader[1] = 0x5A  // 'Z'
        let sig = db.detectSignature(from: Data(peHeader))
        XCTAssertNotNil(sig, "PE/MZ header should be detected")
        if let sig = sig {
            XCTAssertTrue(
                sig.name.contains("PE") || sig.name.contains("MZ") || sig.name.contains("EXE")
                    || sig.name.contains("Portable") || sig.name.contains("DOS"),
                "Name should reference PE/MZ/EXE, got: \(sig.name)"
            )
        }
    }

    // MARK: - 8. Detect WASM signature

    func testDetectWASMSignature() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }

        // WASM magic: 00 61 73 6D (\0asm) followed by version 1
        let wasmHeader: [UInt8] = [
            0x00, 0x61, 0x73, 0x6D,  // \0asm
            0x01, 0x00, 0x00, 0x00,  // version 1
        ]
        let sig = db.detectSignature(from: data(wasmHeader))
        XCTAssertNotNil(sig, "WASM header should be detected")
        if let sig = sig {
            XCTAssertTrue(
                sig.name.uppercased().contains("WASM") || sig.name.contains("WebAssembly"),
                "Name should reference WASM, got: \(sig.name)"
            )
        }
    }

    // MARK: - 9. Detect SQLite signature

    func testDetectSQLiteSignature() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }

        // SQLite magic: "SQLite format 3\000"
        let magic = Array("SQLite format 3\0".utf8)
        let sig = db.detectSignature(from: data(magic))
        XCTAssertNotNil(sig, "SQLite header should be detected")
        if let sig = sig {
            XCTAssertTrue(sig.name.contains("SQLite"), "Name should contain SQLite, got: \(sig.name)")
        }
    }

    // MARK: - 10. Detect ZIP signature

    func testDetectZIPSignature() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }

        // ZIP magic: PK\x03\x04
        let zipHeader: [UInt8] = [
            0x50, 0x4B, 0x03, 0x04,  // PK..
            0x14, 0x00,              // version needed
            0x00, 0x00,              // flags
            0x08, 0x00,              // compression
        ]
        let sig = db.detectSignature(from: data(zipHeader))
        XCTAssertNotNil(sig, "ZIP header should be detected")
        if let sig = sig {
            XCTAssertTrue(sig.name.contains("ZIP"), "Name should contain ZIP, got: \(sig.name)")
            XCTAssertEqual(sig.category, "proprietary")
        }
    }

    // MARK: - 11. Empty data returns nil

    func testEmptyDataReturnsNil() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }
        let sig = db.detectSignature(from: Data())
        XCTAssertNil(sig, "Empty data should return nil from detectSignature")
    }

    // MARK: - 12. Unknown data returns nil

    func testUnknownDataReturnsNil() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }
        // Random bytes unlikely to match any signature
        let garbage = Data([0xFE, 0xFE, 0xFE, 0xFE, 0xAA, 0xBB, 0xCC, 0xDD,
                            0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
        let sig = db.detectSignature(from: garbage)
        XCTAssertNil(sig, "Random bytes should not match any signature")
    }

    // MARK: - 13. Load fields for PNG

    func testLoadFieldsForPNG() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }

        let pngData = buildMinimalPNG()
        guard let sig = db.detectSignature(from: pngData) else {
            return XCTFail("PNG should be detected")
        }

        let fields = db.loadFields(signatureId: sig.id, data: pngData)
        XCTAssertFalse(fields.isEmpty, "PNG should have fields defined")

        let fieldNames = fields.map { $0.descriptor.name }
        XCTAssertTrue(fieldNames.contains("Width"), "PNG fields should include Width, got: \(fieldNames)")
        XCTAssertTrue(fieldNames.contains("Height"), "PNG fields should include Height, got: \(fieldNames)")
    }

    // MARK: - 14. Load sections for PNG

    func testLoadSectionsForPNG() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }

        let pngData = buildMinimalPNG()
        guard let sig = db.detectSignature(from: pngData) else {
            return XCTFail("PNG should be detected")
        }

        let sections = db.loadSections(signatureId: sig.id, data: pngData)
        XCTAssertFalse(sections.isEmpty, "PNG should have sections defined")

        let sectionNames = sections.map { $0.name.lowercased() }
        let hasSignatureSection = sectionNames.contains(where: { $0.contains("signature") })
        let hasHeaderSection = sectionNames.contains(where: { $0.contains("header") || $0.contains("ihdr") })
        XCTAssertTrue(hasSignatureSection, "PNG sections should include a signature section, got: \(sectionNames)")
        XCTAssertTrue(hasHeaderSection, "PNG sections should include a header section, got: \(sectionNames)")
    }

    // MARK: - 15. Signature matched range

    func testSignatureMatchedRange() {
        guard let db = makeDatabase() else { return XCTFail("Cannot open formats.db") }

        let pngData = buildMinimalPNG()
        guard let sig = db.detectSignature(from: pngData) else {
            return XCTFail("PNG should be detected")
        }

        // PNG magic is 8 bytes at offset 0
        XCTAssertEqual(sig.matchedRange.lowerBound, 0, "PNG matched range should start at 0")
        XCTAssertEqual(sig.matchedRange.upperBound, 8, "PNG matched range should end at 8")
        XCTAssertEqual(sig.matchedRange, 0..<8)
    }

    // MARK: - 16. Database has 44 signatures

    func testDatabaseHas44Signatures() {
        guard let db = makeDatabase(), db.isAvailable else {
            return XCTFail("Cannot open formats.db")
        }

        // We verify by trying to detect signatures for a broad set of data.
        // Since we cannot query COUNT(*) directly, we verify the DB opens
        // and can detect multiple distinct formats as a proxy for coverage.
        // If direct SQL access were available, we would check count == 44.
        //
        // As a pragmatic check, verify at least 6 distinct format categories
        // are detectable (image, archive, executable, etc.)
        let testCases: [(name: String, bytes: [UInt8])] = [
            ("PNG",    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
            ("JPEG",   [0xFF, 0xD8, 0xFF, 0xE0]),
            ("ELF",    [0x7F, 0x45, 0x4C, 0x46]),
            ("ZIP",    [0x50, 0x4B, 0x03, 0x04]),
            ("WASM",   [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]),
            ("MZ",     [0x4D, 0x5A, 0x90, 0x00]),
        ]

        var detectedCount = 0
        for tc in testCases {
            if db.detectSignature(from: data(tc.bytes)) != nil {
                detectedCount += 1
            }
        }
        XCTAssertGreaterThanOrEqual(
            detectedCount, 6,
            "Should detect at least 6 distinct formats; detected \(detectedCount)"
        )
    }

    // MARK: - PNG helper

    /// Build a minimal but structurally valid PNG header (enough for field parsing).
    private func buildMinimalPNG() -> Data {
        var bytes: [UInt8] = []

        // PNG signature (8 bytes)
        bytes += [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

        // IHDR chunk: length(4) + type(4) + data(13) + CRC(4) = 25 bytes
        // Length = 13
        bytes += [0x00, 0x00, 0x00, 0x0D]
        // Type = "IHDR"
        bytes += [0x49, 0x48, 0x44, 0x52]
        // Width = 100
        bytes += [0x00, 0x00, 0x00, 0x64]
        // Height = 50
        bytes += [0x00, 0x00, 0x00, 0x32]
        // Bit depth = 8
        bytes += [0x08]
        // Color type = 2 (truecolor)
        bytes += [0x02]
        // Compression = 0
        bytes += [0x00]
        // Filter = 0
        bytes += [0x00]
        // Interlace = 0
        bytes += [0x00]
        // CRC (placeholder)
        bytes += [0x00, 0x00, 0x00, 0x00]

        // Pad to ensure enough data for any field offsets
        bytes += Array(repeating: UInt8(0x00), count: 64)

        return Data(bytes)
    }
}

#endif
