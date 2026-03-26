//
//  FileFormatInterpreterTests.swift
//  qwTests
//
//  Tests for FileFormatInterpreter.swift: field descriptors, byte decoding
//  (indirectly via FileAnnotator.annotate), concrete interpreters, and tooltips.
//  Ticket: T-000071
//

import XCTest

#if os(macOS)
@testable import qw

final class FileFormatInterpreterTests: XCTestCase {

    // MARK: - Helpers

    /// Minimal valid PNG header: 8-byte signature + IHDR chunk (length + type + 13 bytes data).
    /// Total = 8 + 4 + 4 + 13 = 29 bytes minimum; we pad to 33 to satisfy the guard.
    private func makePNGHeader(width: UInt32, height: UInt32, bitDepth: UInt8, colorType: UInt8,
                               compression: UInt8 = 0, filter: UInt8 = 0, interlace: UInt8 = 0) -> Data {
        var data = Data()
        // PNG signature
        data.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        // IHDR length = 13 (big-endian)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(13).bigEndian) { Array($0) })
        // IHDR chunk type
        data.append(contentsOf: [0x49, 0x48, 0x44, 0x52]) // "IHDR"
        // Width (big-endian)
        data.append(contentsOf: withUnsafeBytes(of: width.bigEndian) { Array($0) })
        // Height (big-endian)
        data.append(contentsOf: withUnsafeBytes(of: height.bigEndian) { Array($0) })
        // Bit depth, color type, compression, filter, interlace
        data.append(contentsOf: [bitDepth, colorType, compression, filter, interlace])
        // Pad to at least 33 bytes (CRC placeholder)
        while data.count < 33 {
            data.append(0x00)
        }
        return data
    }

    /// Minimal JPEG/JFIF header: SOI + APP0 marker + length + "JFIF\0" + version + density.
    private func makeJPEGHeader(versionMajor: UInt8 = 1, versionMinor: UInt8 = 1,
                                densityUnits: UInt8 = 1,
                                xDensity: UInt16 = 72, yDensity: UInt16 = 72) -> Data {
        var data = Data()
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        // APP0 marker
        data.append(contentsOf: [0xFF, 0xE0])
        // APP0 length (big-endian) - 16 is typical for basic JFIF
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).bigEndian) { Array($0) })
        // Identifier: "JFIF\0"
        data.append(contentsOf: [0x4A, 0x46, 0x49, 0x46, 0x00])
        // Version
        data.append(contentsOf: [versionMajor, versionMinor])
        // Density units
        data.append(densityUnits)
        // X Density (big-endian)
        data.append(contentsOf: withUnsafeBytes(of: xDensity.bigEndian) { Array($0) })
        // Y Density (big-endian)
        data.append(contentsOf: withUnsafeBytes(of: yDensity.bigEndian) { Array($0) })
        // Pad to 20 bytes minimum
        while data.count < 20 {
            data.append(0x00)
        }
        return data
    }

    /// Minimal ELF header (20+ bytes).
    private func makeELFHeader(elfClass: UInt8 = 2, dataEncoding: UInt8 = 1,
                               elfVersion: UInt8 = 1, osABI: UInt8 = 0,
                               abiVersion: UInt8 = 0,
                               type: UInt16 = 2, machine: UInt16 = 0x3E) -> Data {
        var data = Data()
        // ELF magic: 7F 45 4C 46
        data.append(contentsOf: [0x7F, 0x45, 0x4C, 0x46])
        // Class, Data Encoding, ELF Version, OS/ABI, ABI Version
        data.append(contentsOf: [elfClass, dataEncoding, elfVersion, osABI, abiVersion])
        // Padding: 7 bytes
        data.append(contentsOf: Array(repeating: UInt8(0), count: 7))
        // Type and Machine - endianness determined by dataEncoding byte
        let endianness: Endianness = dataEncoding == 1 ? .little : .big
        if endianness == .little {
            data.append(contentsOf: withUnsafeBytes(of: type.littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: machine.littleEndian) { Array($0) })
        } else {
            data.append(contentsOf: withUnsafeBytes(of: type.bigEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: machine.bigEndian) { Array($0) })
        }
        return data
    }

    private func findField(named name: String, in values: [FieldValue]) -> FieldValue? {
        values.first { $0.descriptor.name == name }
    }

    // MARK: - 1. PNG Header Decoding

    func testPNGHeaderDecoding() {
        let data = makePNGHeader(width: 1920, height: 1080, bitDepth: 8, colorType: 6)
        let annotations = FileAnnotator.annotate(data: data)

        XCTAssertFalse(annotations.isEmpty, "PNG header should produce annotations")

        // Verify signature field
        let sig = findField(named: "PNG Signature", in: annotations)
        XCTAssertNotNil(sig)
        XCTAssertEqual(sig?.displayValue, "89 50 4E 47 0D 0A 1A 0A")

        // Verify IHDR chunk type
        let chunkType = findField(named: "IHDR Chunk Type", in: annotations)
        XCTAssertNotNil(chunkType)
        XCTAssertEqual(chunkType?.displayValue, "IHDR")

        // Verify width
        let width = findField(named: "Width", in: annotations)
        XCTAssertNotNil(width)
        XCTAssertEqual(width?.displayValue, "1920")

        // Verify height
        let height = findField(named: "Height", in: annotations)
        XCTAssertNotNil(height)
        XCTAssertEqual(height?.displayValue, "1080")

        // Verify bit depth
        let bitDepth = findField(named: "Bit Depth", in: annotations)
        XCTAssertNotNil(bitDepth)
        XCTAssertEqual(bitDepth?.displayValue, "8")

        // Verify color type is enriched
        let colorType = findField(named: "Color Type", in: annotations)
        XCTAssertNotNil(colorType)
        XCTAssertEqual(colorType?.displayValue, "6 (RGBA)")
    }

    func testPNGHeaderFieldCount() {
        let data = makePNGHeader(width: 100, height: 200, bitDepth: 8, colorType: 2)
        let annotations = FileAnnotator.annotate(data: data)
        // Full IHDR: signature + IHDR length + chunk type + width + height +
        // bit depth + color type + compression + filter + interlace = 10 fields
        XCTAssertEqual(annotations.count, 10)
    }

    // MARK: - 2. JPEG/JFIF Header Decoding

    func testJPEGHeaderDecoding() {
        let data = makeJPEGHeader(versionMajor: 1, versionMinor: 2,
                                  densityUnits: 1, xDensity: 300, yDensity: 300)
        let annotations = FileAnnotator.annotate(data: data)

        XCTAssertFalse(annotations.isEmpty, "JPEG header should produce annotations")

        let soi = findField(named: "SOI Marker", in: annotations)
        XCTAssertNotNil(soi)
        XCTAssertEqual(soi?.displayValue, "FF D8")

        let app0 = findField(named: "APP0 Marker", in: annotations)
        XCTAssertNotNil(app0)
        XCTAssertEqual(app0?.displayValue, "FF E0")

        let identifier = findField(named: "Identifier", in: annotations)
        XCTAssertNotNil(identifier)
        XCTAssertEqual(identifier?.displayValue, "JFIF")

        let vMajor = findField(named: "Version Major", in: annotations)
        XCTAssertEqual(vMajor?.displayValue, "1")

        let vMinor = findField(named: "Version Minor", in: annotations)
        XCTAssertEqual(vMinor?.displayValue, "2")

        let densityUnits = findField(named: "Density Units", in: annotations)
        XCTAssertNotNil(densityUnits)
        XCTAssertEqual(densityUnits?.displayValue, "1 (Pixels/inch)")

        let xDensity = findField(named: "X Density", in: annotations)
        XCTAssertEqual(xDensity?.displayValue, "300")

        let yDensity = findField(named: "Y Density", in: annotations)
        XCTAssertEqual(yDensity?.displayValue, "300")
    }

    func testJPEGFieldCount() {
        let data = makeJPEGHeader()
        let annotations = FileAnnotator.annotate(data: data)
        // SOI + APP0 marker + APP0 length + Identifier + version major + minor +
        // density units + x density + y density = 9
        XCTAssertEqual(annotations.count, 9)
    }

    // MARK: - 3. ELF Header Decoding (Little-Endian)

    func testELFHeaderLittleEndian() {
        let data = makeELFHeader(elfClass: 2, dataEncoding: 1, osABI: 3,
                                 type: 2, machine: 0x3E)
        let annotations = FileAnnotator.annotate(data: data)

        XCTAssertFalse(annotations.isEmpty, "ELF header should produce annotations")

        let magic = findField(named: "ELF Magic", in: annotations)
        XCTAssertNotNil(magic)
        XCTAssertEqual(magic?.displayValue, "7F 45 4C 46")

        // Display values may include raw prefix from DB (e.g. "2 (64-bit)") or just
        // the name from the hardcoded interpreter (e.g. "64-bit"), so use contains.
        let cls = findField(named: "Class", in: annotations)
        XCTAssertTrue(cls?.displayValue.contains("64-bit") == true, "Got: \(cls?.displayValue ?? "nil")")

        let encoding = findField(named: "Data Encoding", in: annotations)
        XCTAssertTrue(encoding?.displayValue.contains("Little-endian") == true, "Got: \(encoding?.displayValue ?? "nil")")

        let osABI = findField(named: "OS/ABI", in: annotations)
        XCTAssertTrue(osABI?.displayValue.contains("Linux") == true, "Got: \(osABI?.displayValue ?? "nil")")

        let elfType = findField(named: "Type", in: annotations)
        XCTAssertTrue(elfType?.displayValue.contains("Executable") == true, "Got: \(elfType?.displayValue ?? "nil")")

        let machine = findField(named: "Machine", in: annotations)
        XCTAssertTrue(machine?.displayValue.contains("x86-64") == true, "Got: \(machine?.displayValue ?? "nil")")
    }

    // MARK: - 3b. ELF Header Decoding (Big-Endian) via hardcoded interpreter

    func testELFHeaderBigEndian() {
        // Test the hardcoded interpreter directly since the DB always uses little-endian
        // for Type/Machine fields, which would misread big-endian ELF data.
        let data = makeELFHeader(elfClass: 1, dataEncoding: 2, osABI: 0,
                                 type: 3, machine: 0x14)
        let fields = ELFInterpreter.fields(for: data)
        XCTAssertFalse(fields.isEmpty)

        // Verify field endianness is derived from data encoding byte
        let typeField = fields.first { $0.name == "Type" }
        XCTAssertEqual(typeField?.endianness, .big)

        let machineField = fields.first { $0.name == "Machine" }
        XCTAssertEqual(machineField?.endianness, .big)

        // Verify helper methods
        XCTAssertEqual(ELFInterpreter.className(1), "32-bit")
        XCTAssertEqual(ELFInterpreter.dataEncodingName(2), "Big-endian")
        XCTAssertEqual(ELFInterpreter.osABIName(0), "System V")
        XCTAssertEqual(ELFInterpreter.typeName(3), "Shared object")
        XCTAssertEqual(ELFInterpreter.machineName(0x14), "PowerPC")
    }

    // MARK: - 4. Boundary Conditions

    func testEmptyDataReturnsNoAnnotations() {
        let annotations = FileAnnotator.annotate(data: Data())
        XCTAssertTrue(annotations.isEmpty)
    }

    func testDataTooShortForPNGIHDR() {
        // Only the 8-byte PNG signature, not enough for IHDR fields
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                         0x00, 0x00, 0x00]) // only 11 bytes total
        let annotations = FileAnnotator.annotate(data: data)
        // Should still get the signature field, but not the IHDR fields
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations.first?.descriptor.name, "PNG Signature")
    }

    func testDataTooShortForJPEGAPP0() {
        // Test the hardcoded interpreter directly: 5 bytes < 20 needed for APP0
        let data = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
        let fields = JPEGInterpreter.fields(for: data)
        // Hardcoded interpreter requires 20 bytes for APP0 fields, so only SOI returned
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields.first?.name, "SOI Marker")
    }

    func testDataTooShortForELFExtendedFields() {
        // ELF magic only (4 bytes) -- not enough for class/encoding fields
        let data = Data([0x7F, 0x45, 0x4C, 0x46])
        let annotations = FileAnnotator.annotate(data: data)
        // Should only get ELF Magic field
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations.first?.descriptor.name, "ELF Magic")
    }

    // MARK: - 5. uint8 Decoding (PNG Bit Depth)

    func testUInt8DecodingViaBitDepth() {
        let data = makePNGHeader(width: 1, height: 1, bitDepth: 16, colorType: 0)
        let annotations = FileAnnotator.annotate(data: data)
        let bitDepth = findField(named: "Bit Depth", in: annotations)
        XCTAssertEqual(bitDepth?.displayValue, "16")
        XCTAssertEqual(bitDepth?.rawBytes.count, 1)
        XCTAssertEqual(bitDepth?.rawBytes[0], 16)
    }

    // MARK: - 6. uint16 Decoding (JPEG Density, Big Endian)

    func testUInt16BigEndianViaJPEGDensity() {
        let data = makeJPEGHeader(xDensity: 0x0100, yDensity: 0x0048)
        let annotations = FileAnnotator.annotate(data: data)

        let xDensity = findField(named: "X Density", in: annotations)
        XCTAssertEqual(xDensity?.displayValue, "256")
        XCTAssertEqual(xDensity?.descriptor.endianness, .big)

        let yDensity = findField(named: "Y Density", in: annotations)
        XCTAssertEqual(yDensity?.displayValue, "72")
    }

    // MARK: - 7. uint32 Decoding (PNG Width/Height, Big Endian)

    func testUInt32BigEndianViaPNGDimensions() {
        let data = makePNGHeader(width: 4096, height: 2160, bitDepth: 8, colorType: 2)
        let annotations = FileAnnotator.annotate(data: data)

        let width = findField(named: "Width", in: annotations)
        XCTAssertEqual(width?.displayValue, "4096")
        XCTAssertEqual(width?.descriptor.endianness, .big)
        XCTAssertEqual(width?.rawBytes.count, 4)

        let height = findField(named: "Height", in: annotations)
        XCTAssertEqual(height?.displayValue, "2160")
    }

    // MARK: - 8. ASCII Decoding (JPEG Identifier)

    func testASCIIDecodingViaJPEGIdentifier() {
        let data = makeJPEGHeader()
        let annotations = FileAnnotator.annotate(data: data)
        let identifier = findField(named: "Identifier", in: annotations)
        XCTAssertNotNil(identifier)
        XCTAssertEqual(identifier?.displayValue, "JFIF")
        XCTAssertEqual(identifier?.descriptor.type, .ascii)
        // Raw bytes should be "JFIF\0"
        XCTAssertEqual(identifier?.rawBytes, Data([0x4A, 0x46, 0x49, 0x46, 0x00]))
    }

    // MARK: - 9. Magic/Bytes Decoding (PNG Signature)

    func testMagicBytesDecodingViaPNGSignature() {
        let data = makePNGHeader(width: 1, height: 1, bitDepth: 8, colorType: 0)
        let annotations = FileAnnotator.annotate(data: data)
        let sig = findField(named: "PNG Signature", in: annotations)
        XCTAssertNotNil(sig)
        XCTAssertEqual(sig?.descriptor.type, .magic)
        XCTAssertEqual(sig?.displayValue, "89 50 4E 47 0D 0A 1A 0A")
        XCTAssertEqual(sig?.rawBytes, Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    func testBytesFieldDecodingViaELFPadding() {
        let data = makeELFHeader()
        let annotations = FileAnnotator.annotate(data: data)
        let padding = findField(named: "Padding", in: annotations)
        XCTAssertNotNil(padding)
        XCTAssertEqual(padding?.descriptor.type, .bytes)
        XCTAssertEqual(padding?.descriptor.size, 7)
        XCTAssertEqual(padding?.displayValue, "00 00 00 00 00 00 00")
    }

    // MARK: - 10. Tooltip

    func testTooltipHit() {
        let data = makePNGHeader(width: 640, height: 480, bitDepth: 8, colorType: 2)
        let annotations = FileAnnotator.annotate(data: data)

        // Byte 0 is within "PNG Signature" (offset 0, size 8)
        let tip0 = FileAnnotator.tooltip(for: 0, in: annotations)
        XCTAssertNotNil(tip0)
        XCTAssertTrue(tip0!.contains("PNG Signature"))

        // Byte 7 is still within the signature
        let tip7 = FileAnnotator.tooltip(for: 7, in: annotations)
        XCTAssertNotNil(tip7)
        XCTAssertTrue(tip7!.contains("PNG Signature"))

        // Byte 16 is within "Width" (offset 16, size 4)
        let tipWidth = FileAnnotator.tooltip(for: 16, in: annotations)
        XCTAssertNotNil(tipWidth)
        XCTAssertTrue(tipWidth!.contains("Width"))
        XCTAssertTrue(tipWidth!.contains("640"))
    }

    func testTooltipMiss() {
        let data = makePNGHeader(width: 1, height: 1, bitDepth: 8, colorType: 0)
        let annotations = FileAnnotator.annotate(data: data)

        // Byte 100 is well past any annotated field
        let tip = FileAnnotator.tooltip(for: 100, in: annotations)
        XCTAssertNil(tip)
    }

    func testTooltipEmptyAnnotations() {
        let tip = FileAnnotator.tooltip(for: 0, in: [])
        XCTAssertNil(tip)
    }

    // MARK: - 11. PNGInterpreter.colorTypeName

    func testColorTypeName() {
        XCTAssertEqual(PNGInterpreter.colorTypeName(0), "Grayscale")
        XCTAssertEqual(PNGInterpreter.colorTypeName(2), "RGB")
        XCTAssertEqual(PNGInterpreter.colorTypeName(3), "Indexed")
        XCTAssertEqual(PNGInterpreter.colorTypeName(4), "Grayscale+Alpha")
        XCTAssertEqual(PNGInterpreter.colorTypeName(6), "RGBA")
        XCTAssertEqual(PNGInterpreter.colorTypeName(99), "Unknown (99)")
    }

    // MARK: - 12. ELFInterpreter Helpers

    func testELFClassName() {
        XCTAssertEqual(ELFInterpreter.className(1), "32-bit")
        XCTAssertEqual(ELFInterpreter.className(2), "64-bit")
        XCTAssertEqual(ELFInterpreter.className(0), "Unknown (0)")
    }

    func testELFDataEncodingName() {
        XCTAssertEqual(ELFInterpreter.dataEncodingName(1), "Little-endian")
        XCTAssertEqual(ELFInterpreter.dataEncodingName(2), "Big-endian")
        XCTAssertEqual(ELFInterpreter.dataEncodingName(5), "Unknown (5)")
    }

    func testELFOsABIName() {
        XCTAssertEqual(ELFInterpreter.osABIName(0), "System V")
        XCTAssertEqual(ELFInterpreter.osABIName(1), "HP-UX")
        XCTAssertEqual(ELFInterpreter.osABIName(2), "NetBSD")
        XCTAssertEqual(ELFInterpreter.osABIName(3), "Linux")
        XCTAssertEqual(ELFInterpreter.osABIName(6), "Solaris")
        XCTAssertEqual(ELFInterpreter.osABIName(9), "FreeBSD")
        XCTAssertEqual(ELFInterpreter.osABIName(12), "OpenBSD")
        XCTAssertEqual(ELFInterpreter.osABIName(255), "Other (255)")
    }

    func testELFTypeName() {
        XCTAssertEqual(ELFInterpreter.typeName(0), "None")
        XCTAssertEqual(ELFInterpreter.typeName(1), "Relocatable")
        XCTAssertEqual(ELFInterpreter.typeName(2), "Executable")
        XCTAssertEqual(ELFInterpreter.typeName(3), "Shared object")
        XCTAssertEqual(ELFInterpreter.typeName(4), "Core")
        XCTAssertEqual(ELFInterpreter.typeName(99), "Unknown (99)")
    }

    func testELFMachineName() {
        XCTAssertEqual(ELFInterpreter.machineName(0x03), "x86")
        XCTAssertEqual(ELFInterpreter.machineName(0x08), "MIPS")
        XCTAssertEqual(ELFInterpreter.machineName(0x14), "PowerPC")
        XCTAssertEqual(ELFInterpreter.machineName(0x28), "ARM")
        XCTAssertEqual(ELFInterpreter.machineName(0x3E), "x86-64")
        XCTAssertEqual(ELFInterpreter.machineName(0xB7), "AArch64")
        XCTAssertEqual(ELFInterpreter.machineName(0xF3), "RISC-V")
        XCTAssertEqual(ELFInterpreter.machineName(0xFF), "Other (0xFF)")
    }

    // MARK: - 13. Unknown Format Returns Empty

    func testUnknownFormatReturnsEmpty() {
        // Random bytes that don't match any known signature
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02, 0x03,
                         0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B])
        let annotations = FileAnnotator.annotate(data: data)
        XCTAssertTrue(annotations.isEmpty, "Unknown format should produce no annotations")
    }

    // MARK: - Additional: JPEGInterpreter.densityUnitsName

    func testJPEGDensityUnitsName() {
        XCTAssertEqual(JPEGInterpreter.densityUnitsName(0), "No units (aspect ratio)")
        XCTAssertEqual(JPEGInterpreter.densityUnitsName(1), "Pixels/inch")
        XCTAssertEqual(JPEGInterpreter.densityUnitsName(2), "Pixels/cm")
        XCTAssertEqual(JPEGInterpreter.densityUnitsName(99), "Unknown (99)")
    }

    // MARK: - Additional: JPEG without APP0 marker

    func testJPEGWithoutAPP0OnlyGetSOI() {
        // Test the hardcoded interpreter: SOI + non-APP0 marker (APP1 = FF E1)
        var data = Data([0xFF, 0xD8, 0xFF, 0xE1])
        data.append(contentsOf: Array(repeating: UInt8(0), count: 16))
        let fields = JPEGInterpreter.fields(for: data)
        // Hardcoded interpreter checks for APP0 (FF E0), so only SOI returned
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields.first?.name, "SOI Marker")
    }

    // MARK: - Additional: Field descriptor properties

    func testPNGFieldDescriptors() {
        let data = makePNGHeader(width: 1, height: 1, bitDepth: 8, colorType: 0)
        let fields = PNGInterpreter.fields(for: data)

        let sigField = fields.first { $0.name == "PNG Signature" }
        XCTAssertEqual(sigField?.offset, 0)
        XCTAssertEqual(sigField?.size, 8)
        XCTAssertEqual(sigField?.type, .magic)

        let widthField = fields.first { $0.name == "Width" }
        XCTAssertEqual(widthField?.offset, 16)
        XCTAssertEqual(widthField?.size, 4)
        XCTAssertEqual(widthField?.type, .uint32)
        XCTAssertEqual(widthField?.endianness, .big)
    }

    // MARK: - Additional: ELF endianness applied to Type/Machine fields

    func testELFFieldEndiannessDeterminedByDataByte() {
        // Little-endian ELF
        let leData = makeELFHeader(dataEncoding: 1)
        let leFields = ELFInterpreter.fields(for: leData)
        let leType = leFields.first { $0.name == "Type" }
        XCTAssertEqual(leType?.endianness, .little)

        // Big-endian ELF
        let beData = makeELFHeader(dataEncoding: 2)
        let beFields = ELFInterpreter.fields(for: beData)
        let beType = beFields.first { $0.name == "Type" }
        XCTAssertEqual(beType?.endianness, .big)
    }

    // MARK: - Additional: PNG color type enrichment for all types

    func testPNGColorTypeEnrichmentGrayscale() {
        let data = makePNGHeader(width: 1, height: 1, bitDepth: 8, colorType: 0)
        let annotations = FileAnnotator.annotate(data: data)
        let ct = findField(named: "Color Type", in: annotations)
        XCTAssertEqual(ct?.displayValue, "0 (Grayscale)")
    }

    func testPNGColorTypeEnrichmentRGB() {
        let data = makePNGHeader(width: 1, height: 1, bitDepth: 8, colorType: 2)
        let annotations = FileAnnotator.annotate(data: data)
        let ct = findField(named: "Color Type", in: annotations)
        XCTAssertEqual(ct?.displayValue, "2 (RGB)")
    }

    func testPNGColorTypeEnrichmentIndexed() {
        let data = makePNGHeader(width: 1, height: 1, bitDepth: 8, colorType: 3)
        let annotations = FileAnnotator.annotate(data: data)
        let ct = findField(named: "Color Type", in: annotations)
        XCTAssertEqual(ct?.displayValue, "3 (Indexed)")
    }

    // MARK: - Additional: JPEG density units enrichment

    func testJPEGDensityUnitsEnrichmentNoUnits() {
        let data = makeJPEGHeader(densityUnits: 0)
        let annotations = FileAnnotator.annotate(data: data)
        let du = findField(named: "Density Units", in: annotations)
        XCTAssertEqual(du?.displayValue, "0 (No units (aspect ratio))")
    }

    func testJPEGDensityUnitsEnrichmentPixelsPerCm() {
        let data = makeJPEGHeader(densityUnits: 2)
        let annotations = FileAnnotator.annotate(data: data)
        let du = findField(named: "Density Units", in: annotations)
        XCTAssertEqual(du?.displayValue, "2 (Pixels/cm)")
    }
}

#endif
