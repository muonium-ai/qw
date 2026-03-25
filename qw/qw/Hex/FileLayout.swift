//
//  FileLayout.swift
//  qw
//
//  Parses binary file structure into labeled sections for hex view highlighting.
//  Ticket: T-000026
//

import SwiftUI

// MARK: - Section model

/// The kind of section within a binary file.
enum SectionKind {
    case signature
    case header
    case metadata
    case data
    case footer
    case chunk

    /// Background color for hex view highlighting.
    var color: Color {
        switch self {
        case .signature: return .purple
        case .header:    return .blue
        case .metadata:  return .green
        case .data:      return .clear
        case .footer:    return .orange
        case .chunk:     return .teal
        }
    }

    /// Human-readable label for the legend.
    var label: String {
        switch self {
        case .signature: return "Signature"
        case .header:    return "Header"
        case .metadata:  return "Metadata"
        case .data:      return "Data"
        case .footer:    return "Footer"
        case .chunk:     return "Chunk"
        }
    }
}

/// A contiguous section of a binary file with a name, byte range, kind, and description.
struct FileSection: Identifiable {
    let id = UUID()
    let name: String
    let range: Range<Int>
    let kind: SectionKind
    let description: String
}

// MARK: - Layout protocol

/// A type that can parse binary data into structural sections.
protocol FileLayout {
    static func parse(data: Data) -> [FileSection]
}

// MARK: - PNG layout

/// Parses PNG files: 8-byte signature followed by length(4)+type(4)+data+CRC(4) chunks.
enum PNGLayout: FileLayout {
    static func parse(data: Data) -> [FileSection] {
        guard data.count >= 8 else { return [] }
        var sections: [FileSection] = []

        sections.append(FileSection(
            name: "PNG Signature",
            range: 0..<8,
            kind: .signature,
            description: "8-byte PNG file signature (\\x89PNG\\r\\n\\x1a\\n)"
        ))

        var offset = 8
        while offset + 8 <= data.count {
            // 4-byte big-endian length
            let length = Int(readUInt32BE(data, at: offset))
            let typeStart = offset + 4
            let typeEnd = typeStart + 4
            guard typeEnd <= data.count else { break }

            let typeBytes = data[data.startIndex + typeStart ..< data.startIndex + typeEnd]
            let typeName = String(bytes: typeBytes, encoding: .ascii) ?? "????"

            // Total chunk size: 4 (length) + 4 (type) + length (data) + 4 (CRC)
            let chunkSize = 4 + 4 + length + 4
            let chunkEnd = min(offset + chunkSize, data.count)

            let kind: SectionKind
            let desc: String
            switch typeName {
            case "IHDR":
                kind = .header
                desc = "Image header: width, height, bit depth, color type"
            case "IDAT":
                kind = .data
                desc = "Compressed image data"
            case "IEND":
                kind = .footer
                desc = "Image end marker (0 bytes payload)"
            case "PLTE":
                kind = .metadata
                desc = "Palette table"
            case "tEXt", "zTXt", "iTXt":
                kind = .metadata
                desc = "Text metadata chunk"
            case "gAMA":
                kind = .metadata
                desc = "Gamma correction value"
            case "cHRM":
                kind = .metadata
                desc = "Primary chromaticities and white point"
            case "sRGB":
                kind = .metadata
                desc = "Standard RGB color space"
            case "iCCP":
                kind = .metadata
                desc = "Embedded ICC profile"
            case "pHYs":
                kind = .metadata
                desc = "Physical pixel dimensions"
            case "tIME":
                kind = .metadata
                desc = "Last modification time"
            default:
                kind = .chunk
                desc = "PNG chunk: \(typeName) (\(length) bytes)"
            }

            sections.append(FileSection(
                name: typeName,
                range: offset..<chunkEnd,
                kind: kind,
                description: desc
            ))

            offset = chunkEnd
            if typeName == "IEND" { break }
        }

        return sections
    }
}

// MARK: - JPEG layout

/// Parses JPEG files: SOI marker, APP/metadata segments, SOS + image data, EOI.
enum JPEGLayout: FileLayout {
    static func parse(data: Data) -> [FileSection] {
        guard data.count >= 2 else { return [] }
        var sections: [FileSection] = []

        // SOI
        sections.append(FileSection(
            name: "SOI",
            range: 0..<2,
            kind: .signature,
            description: "Start of Image marker (FF D8)"
        ))

        var offset = 2
        while offset + 1 < data.count {
            let b0 = data[data.startIndex + offset]
            guard b0 == 0xFF else {
                // Not a marker; skip
                offset += 1
                continue
            }
            let marker = data[data.startIndex + offset + 1]

            // Skip padding FF bytes
            if marker == 0xFF {
                offset += 1
                continue
            }

            // EOI
            if marker == 0xD9 {
                sections.append(FileSection(
                    name: "EOI",
                    range: offset..<min(offset + 2, data.count),
                    kind: .footer,
                    description: "End of Image marker (FF D9)"
                ))
                break
            }

            // SOS: start of scan, followed by entropy-coded data until EOI
            if marker == 0xDA {
                // The SOS header has a length field
                guard offset + 4 <= data.count else { break }
                let segLen = Int(readUInt16BE(data, at: offset + 2))
                let headerEnd = min(offset + 2 + segLen, data.count)

                sections.append(FileSection(
                    name: "SOS",
                    range: offset..<headerEnd,
                    kind: .header,
                    description: "Start of Scan header"
                ))

                // Entropy-coded data runs until FF D9
                let dataStart = headerEnd
                var scanEnd = dataStart
                while scanEnd + 1 < data.count {
                    if data[data.startIndex + scanEnd] == 0xFF &&
                       data[data.startIndex + scanEnd + 1] == 0xD9 {
                        break
                    }
                    scanEnd += 1
                }
                if scanEnd > dataStart {
                    sections.append(FileSection(
                        name: "Image Data",
                        range: dataStart..<scanEnd,
                        kind: .data,
                        description: "Entropy-coded image data"
                    ))
                }
                offset = scanEnd
                continue
            }

            // Markers without a length field (standalone)
            if marker >= 0xD0 && marker <= 0xD7 {
                // RST markers
                sections.append(FileSection(
                    name: String(format: "RST%d", marker - 0xD0),
                    range: offset..<offset + 2,
                    kind: .chunk,
                    description: "Restart marker"
                ))
                offset += 2
                continue
            }

            // Standard segment with 2-byte length
            guard offset + 4 <= data.count else { break }
            let segLength = Int(readUInt16BE(data, at: offset + 2))
            let segEnd = min(offset + 2 + segLength, data.count)

            let name: String
            let kind: SectionKind
            let desc: String
            switch marker {
            case 0xE0:
                name = "APP0"
                kind = .metadata
                desc = "JFIF application segment"
            case 0xE1:
                name = "APP1"
                kind = .metadata
                desc = "EXIF / XMP metadata segment"
            case 0xE2...0xEF:
                name = String(format: "APP%d", marker - 0xE0)
                kind = .metadata
                desc = "Application-specific segment"
            case 0xC0:
                name = "SOF0"
                kind = .header
                desc = "Start of Frame (baseline DCT)"
            case 0xC2:
                name = "SOF2"
                kind = .header
                desc = "Start of Frame (progressive DCT)"
            case 0xC4:
                name = "DHT"
                kind = .metadata
                desc = "Define Huffman Table"
            case 0xDB:
                name = "DQT"
                kind = .metadata
                desc = "Define Quantization Table"
            case 0xDD:
                name = "DRI"
                kind = .metadata
                desc = "Define Restart Interval"
            case 0xFE:
                name = "COM"
                kind = .metadata
                desc = "Comment segment"
            default:
                name = String(format: "FF %02X", marker)
                kind = .chunk
                desc = String(format: "JPEG segment 0x%02X (%d bytes)", marker, segLength)
            }

            sections.append(FileSection(
                name: name,
                range: offset..<segEnd,
                kind: kind,
                description: desc
            ))
            offset = segEnd
        }

        return sections
    }
}

// MARK: - PDF layout

/// Parses PDF files: header line, body, xref table, and trailer (%%EOF).
enum PDFLayout: FileLayout {
    static func parse(data: Data) -> [FileSection] {
        guard data.count >= 5 else { return [] }
        var sections: [FileSection] = []

        // Header: %PDF-x.x plus the newline
        var headerEnd = 0
        for i in 0..<min(data.count, 32) {
            if data[data.startIndex + i] == 0x0A || data[data.startIndex + i] == 0x0D {
                headerEnd = i + 1
                // Handle \r\n
                if headerEnd < data.count && data[data.startIndex + i] == 0x0D &&
                   data[data.startIndex + headerEnd] == 0x0A {
                    headerEnd += 1
                }
                break
            }
        }
        if headerEnd == 0 { headerEnd = min(8, data.count) }

        sections.append(FileSection(
            name: "PDF Header",
            range: 0..<headerEnd,
            kind: .header,
            description: "PDF version header (e.g. %PDF-1.7)"
        ))

        // Search backwards for %%EOF
        let eofMarker: [UInt8] = [0x25, 0x25, 0x45, 0x4F, 0x46] // %%EOF
        var eofStart: Int?
        if data.count >= eofMarker.count {
            let searchStart = max(0, data.count - 64)
            for i in stride(from: data.count - eofMarker.count, through: searchStart, by: -1) {
                let match = eofMarker.enumerated().allSatisfy { j, b in
                    data[data.startIndex + i + j] == b
                }
                if match {
                    eofStart = i
                    break
                }
            }
        }

        // Search backwards for "xref" or "startxref"
        let xrefMarker: [UInt8] = [0x78, 0x72, 0x65, 0x66] // "xref"
        var xrefStart: Int?
        if let eof = eofStart {
            let searchStart = max(headerEnd, eof - 4096)
            for i in stride(from: eof - 1, through: searchStart, by: -1) {
                guard i + xrefMarker.count <= data.count else { continue }
                let match = xrefMarker.enumerated().allSatisfy { j, b in
                    data[data.startIndex + i + j] == b
                }
                if match {
                    xrefStart = i
                    break
                }
            }
        }

        // Body
        let bodyEnd = xrefStart ?? eofStart ?? data.count
        if headerEnd < bodyEnd {
            sections.append(FileSection(
                name: "PDF Body",
                range: headerEnd..<bodyEnd,
                kind: .data,
                description: "PDF objects (streams, fonts, pages, etc.)"
            ))
        }

        // Xref + trailer
        if let xref = xrefStart {
            let trailerEnd = eofStart ?? data.count
            sections.append(FileSection(
                name: "Cross-Reference",
                range: xref..<trailerEnd,
                kind: .metadata,
                description: "Cross-reference table and trailer dictionary"
            ))
        }

        // %%EOF
        if let eof = eofStart {
            sections.append(FileSection(
                name: "%%EOF",
                range: eof..<data.count,
                kind: .footer,
                description: "End-of-file marker"
            ))
        }

        return sections
    }
}

// MARK: - ELF layout

/// Parses ELF files: 64-byte header, program headers, and section headers.
enum ELFLayout: FileLayout {
    static func parse(data: Data) -> [FileSection] {
        guard data.count >= 64 else { return [] }
        var sections: [FileSection] = []

        // Determine 32 vs 64-bit from EI_CLASS (byte 4)
        let eiClass = data[data.startIndex + 4]
        let is64 = (eiClass == 2)
        let headerSize = is64 ? 64 : 52

        sections.append(FileSection(
            name: "ELF Header",
            range: 0..<min(headerSize, data.count),
            kind: .header,
            description: is64 ? "ELF 64-bit header" : "ELF 32-bit header"
        ))

        // EI_DATA (byte 5): 1 = little-endian, 2 = big-endian
        let isLE = data[data.startIndex + 5] == 1

        if is64 && data.count >= 64 {
            // e_phoff at offset 32 (8 bytes), e_shoff at 40 (8 bytes)
            // e_phentsize at 54 (2), e_phnum at 56 (2)
            // e_shentsize at 58 (2), e_shnum at 60 (2)
            let phoff = Int(readUInt64(data, at: 32, littleEndian: isLE))
            let shoff = Int(readUInt64(data, at: 40, littleEndian: isLE))
            let phentsize = Int(readUInt16(data, at: 54, littleEndian: isLE))
            let phnum = Int(readUInt16(data, at: 56, littleEndian: isLE))
            let shentsize = Int(readUInt16(data, at: 58, littleEndian: isLE))
            let shnum = Int(readUInt16(data, at: 60, littleEndian: isLE))

            if phoff > 0 && phnum > 0 {
                let phSize = phentsize * phnum
                let phEnd = min(phoff + phSize, data.count)
                if phoff < data.count {
                    sections.append(FileSection(
                        name: "Program Headers",
                        range: phoff..<phEnd,
                        kind: .metadata,
                        description: "\(phnum) program header entries (\(phentsize) bytes each)"
                    ))
                }
            }

            if shoff > 0 && shnum > 0 {
                let shSize = shentsize * shnum
                let shEnd = min(shoff + shSize, data.count)
                if shoff < data.count {
                    sections.append(FileSection(
                        name: "Section Headers",
                        range: shoff..<shEnd,
                        kind: .metadata,
                        description: "\(shnum) section header entries (\(shentsize) bytes each)"
                    ))
                }
            }
        } else if !is64 && data.count >= 52 {
            // 32-bit ELF
            let phoff = Int(readUInt32(data, at: 28, littleEndian: isLE))
            let shoff = Int(readUInt32(data, at: 32, littleEndian: isLE))
            let phentsize = Int(readUInt16(data, at: 42, littleEndian: isLE))
            let phnum = Int(readUInt16(data, at: 44, littleEndian: isLE))
            let shentsize = Int(readUInt16(data, at: 46, littleEndian: isLE))
            let shnum = Int(readUInt16(data, at: 48, littleEndian: isLE))

            if phoff > 0 && phnum > 0 {
                let phEnd = min(phoff + phentsize * phnum, data.count)
                if phoff < data.count {
                    sections.append(FileSection(
                        name: "Program Headers",
                        range: phoff..<phEnd,
                        kind: .metadata,
                        description: "\(phnum) program header entries (\(phentsize) bytes each)"
                    ))
                }
            }

            if shoff > 0 && shnum > 0 {
                let shEnd = min(shoff + shentsize * shnum, data.count)
                if shoff < data.count {
                    sections.append(FileSection(
                        name: "Section Headers",
                        range: shoff..<shEnd,
                        kind: .metadata,
                        description: "\(shnum) section header entries (\(shentsize) bytes each)"
                    ))
                }
            }
        }

        return sections
    }
}

// MARK: - File layout detector

/// Detects the file type using `MagicBytes` and returns the structural layout.
/// Tries the SQLite format database first for static section definitions,
/// then falls back to the hardcoded format-specific parsers.
enum FileLayoutDetector {
    static func detect(data: Data) -> [FileSection] {
        guard let sig = MagicBytes.detect(from: data) else { return [] }

        // Try database-backed sections first
        let db = FormatDatabase.shared
        if db.isAvailable, let dbSig = db.detectSignature(from: data) {
            let dbSections = db.loadSections(signatureId: dbSig.id, data: data)
            if !dbSections.isEmpty {
                return dbSections
            }
        }

        // Fall back to hardcoded parsers
        switch sig.name {
        case "PNG Image":
            return PNGLayout.parse(data: data)
        case "JPEG Image":
            return JPEGLayout.parse(data: data)
        case "PDF Document":
            return PDFLayout.parse(data: data)
        case "ELF Executable":
            return ELFLayout.parse(data: data)
        default:
            return []
        }
    }
}

// MARK: - Binary reading helpers

private func readUInt16BE(_ data: Data, at offset: Int) -> UInt16 {
    let base = data.startIndex + offset
    return UInt16(data[base]) << 8 | UInt16(data[base + 1])
}

private func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
    let base = data.startIndex + offset
    return UInt32(data[base]) << 24 |
           UInt32(data[base + 1]) << 16 |
           UInt32(data[base + 2]) << 8 |
           UInt32(data[base + 3])
}

private func readUInt16(_ data: Data, at offset: Int, littleEndian: Bool) -> UInt16 {
    let base = data.startIndex + offset
    if littleEndian {
        return UInt16(data[base]) | UInt16(data[base + 1]) << 8
    } else {
        return UInt16(data[base]) << 8 | UInt16(data[base + 1])
    }
}

private func readUInt32(_ data: Data, at offset: Int, littleEndian: Bool) -> UInt32 {
    let base = data.startIndex + offset
    if littleEndian {
        return UInt32(data[base]) |
               UInt32(data[base + 1]) << 8 |
               UInt32(data[base + 2]) << 16 |
               UInt32(data[base + 3]) << 24
    } else {
        return UInt32(data[base]) << 24 |
               UInt32(data[base + 1]) << 16 |
               UInt32(data[base + 2]) << 8 |
               UInt32(data[base + 3])
    }
}

private func readUInt64(_ data: Data, at offset: Int, littleEndian: Bool) -> UInt64 {
    let base = data.startIndex + offset
    if littleEndian {
        return UInt64(data[base]) |
               UInt64(data[base + 1]) << 8 |
               UInt64(data[base + 2]) << 16 |
               UInt64(data[base + 3]) << 24 |
               UInt64(data[base + 4]) << 32 |
               UInt64(data[base + 5]) << 40 |
               UInt64(data[base + 6]) << 48 |
               UInt64(data[base + 7]) << 56
    } else {
        return UInt64(data[base]) << 56 |
               UInt64(data[base + 1]) << 48 |
               UInt64(data[base + 2]) << 40 |
               UInt64(data[base + 3]) << 32 |
               UInt64(data[base + 4]) << 24 |
               UInt64(data[base + 5]) << 16 |
               UInt64(data[base + 6]) << 8 |
               UInt64(data[base + 7])
    }
}
