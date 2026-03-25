//
//  FileFormatInterpreter.swift
//  qw
//
//  Inline byte interpretation: describes known fields in binary file headers
//  and decodes their values for annotation in the hex view.
//  Ticket: T-000027
//

import Foundation

// MARK: - Field types

/// The data type used to decode a field's raw bytes.
enum FieldType {
    case uint8, uint16, uint32, uint64
    case int8, int16, int32, int64
    case float32, float64
    case ascii
    case bytes
    case magic
}

/// Byte order for multi-byte fields.
enum Endianness {
    case big, little
}

// MARK: - Field descriptor

/// Describes a single known field within a binary format header.
struct FieldDescriptor {
    let name: String
    let offset: Int
    let size: Int
    let type: FieldType
    let endianness: Endianness
}

// MARK: - Field value (decoded)

/// A field descriptor paired with its raw bytes and a human-readable decoded value.
struct FieldValue {
    let descriptor: FieldDescriptor
    let rawBytes: Data
    let displayValue: String
}

// MARK: - Interpreter protocol

/// Implementations know how to describe the header fields for a particular
/// binary file format.
protocol FileFormatInterpreter {
    static func fields(for data: Data) -> [FieldDescriptor]
}

// MARK: - Byte decoding helpers

private enum ByteDecoder {
    static func readUInt8(from data: Data, at offset: Int) -> UInt8? {
        guard offset < data.count else { return nil }
        return data[data.startIndex + offset]
    }

    static func readUInt16(from data: Data, at offset: Int, endianness: Endianness) -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        var value: UInt16 = 0
        let slice = data[(data.startIndex + offset)..<(data.startIndex + offset + 2)]
        withUnsafeMutableBytes(of: &value) { buf in
            slice.copyBytes(to: buf.bindMemory(to: UInt8.self))
        }
        return endianness == .big ? UInt16(bigEndian: value) : UInt16(littleEndian: value)
    }

    static func readUInt32(from data: Data, at offset: Int, endianness: Endianness) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        var value: UInt32 = 0
        let slice = data[(data.startIndex + offset)..<(data.startIndex + offset + 4)]
        withUnsafeMutableBytes(of: &value) { buf in
            slice.copyBytes(to: buf.bindMemory(to: UInt8.self))
        }
        return endianness == .big ? UInt32(bigEndian: value) : UInt32(littleEndian: value)
    }

    static func readUInt64(from data: Data, at offset: Int, endianness: Endianness) -> UInt64? {
        guard offset + 8 <= data.count else { return nil }
        var value: UInt64 = 0
        let slice = data[(data.startIndex + offset)..<(data.startIndex + offset + 8)]
        withUnsafeMutableBytes(of: &value) { buf in
            slice.copyBytes(to: buf.bindMemory(to: UInt8.self))
        }
        return endianness == .big ? UInt64(bigEndian: value) : UInt64(littleEndian: value)
    }

    /// Decode a `FieldDescriptor` against raw data into a human-readable string.
    static func decode(field: FieldDescriptor, from data: Data) -> String {
        let offset = field.offset
        guard offset + field.size <= data.count else { return "\u{2014}" }

        switch field.type {
        case .uint8:
            guard let v = readUInt8(from: data, at: offset) else { return "\u{2014}" }
            return "\(v)"
        case .uint16:
            guard let v = readUInt16(from: data, at: offset, endianness: field.endianness) else { return "\u{2014}" }
            return "\(v)"
        case .uint32:
            guard let v = readUInt32(from: data, at: offset, endianness: field.endianness) else { return "\u{2014}" }
            return "\(v)"
        case .uint64:
            guard let v = readUInt64(from: data, at: offset, endianness: field.endianness) else { return "\u{2014}" }
            return "\(v)"
        case .int8:
            guard let v = readUInt8(from: data, at: offset) else { return "\u{2014}" }
            return "\(Int8(bitPattern: v))"
        case .int16:
            guard let v = readUInt16(from: data, at: offset, endianness: field.endianness) else { return "\u{2014}" }
            return "\(Int16(bitPattern: v))"
        case .int32:
            guard let v = readUInt32(from: data, at: offset, endianness: field.endianness) else { return "\u{2014}" }
            return "\(Int32(bitPattern: v))"
        case .int64:
            guard let v = readUInt64(from: data, at: offset, endianness: field.endianness) else { return "\u{2014}" }
            return "\(Int64(bitPattern: v))"
        case .float32:
            guard let bits = readUInt32(from: data, at: offset, endianness: field.endianness) else { return "\u{2014}" }
            let value = Float(bitPattern: bits)
            if value.isNaN { return "NaN" }
            return "\(value)"
        case .float64:
            guard let bits = readUInt64(from: data, at: offset, endianness: field.endianness) else { return "\u{2014}" }
            let value = Double(bitPattern: bits)
            if value.isNaN { return "NaN" }
            return "\(value)"
        case .ascii:
            let start = data.startIndex + offset
            let end = start + field.size
            let slice = data[start..<end]
            // Strip trailing nulls
            let trimmed = slice.prefix(while: { $0 != 0 })
            return String(data: Data(trimmed), encoding: .ascii) ?? "\u{2014}"
        case .bytes, .magic:
            let start = data.startIndex + offset
            let end = start + field.size
            return data[start..<end].map { String(format: "%02X", $0) }.joined(separator: " ")
        }
    }
}

// MARK: - PNG interpreter

struct PNGInterpreter: FileFormatInterpreter {

    static func fields(for data: Data) -> [FieldDescriptor] {
        var fields: [FieldDescriptor] = []

        // PNG signature: 8 bytes
        fields.append(FieldDescriptor(name: "PNG Signature", offset: 0, size: 8, type: .magic, endianness: .big))

        guard data.count >= 33 else { return fields } // need at least through IHDR

        // IHDR chunk: length(4) + "IHDR"(4) + data(13) starting at offset 8
        fields.append(FieldDescriptor(name: "IHDR Length", offset: 8, size: 4, type: .uint32, endianness: .big))
        fields.append(FieldDescriptor(name: "IHDR Chunk Type", offset: 12, size: 4, type: .ascii, endianness: .big))
        fields.append(FieldDescriptor(name: "Width", offset: 16, size: 4, type: .uint32, endianness: .big))
        fields.append(FieldDescriptor(name: "Height", offset: 20, size: 4, type: .uint32, endianness: .big))
        fields.append(FieldDescriptor(name: "Bit Depth", offset: 24, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "Color Type", offset: 25, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "Compression", offset: 26, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "Filter", offset: 27, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "Interlace", offset: 28, size: 1, type: .uint8, endianness: .big))

        return fields
    }

    /// Map PNG color type byte to a human-readable name.
    static func colorTypeName(_ value: UInt8) -> String {
        switch value {
        case 0: return "Grayscale"
        case 2: return "RGB"
        case 3: return "Indexed"
        case 4: return "Grayscale+Alpha"
        case 6: return "RGBA"
        default: return "Unknown (\(value))"
        }
    }
}

// MARK: - JPEG interpreter

struct JPEGInterpreter: FileFormatInterpreter {

    static func fields(for data: Data) -> [FieldDescriptor] {
        var fields: [FieldDescriptor] = []

        // SOI marker
        fields.append(FieldDescriptor(name: "SOI Marker", offset: 0, size: 2, type: .magic, endianness: .big))

        // Check for APP0 (JFIF) marker: FF E0
        guard data.count >= 20 else { return fields }
        guard data[data.startIndex + 2] == 0xFF,
              data[data.startIndex + 3] == 0xE0 else { return fields }

        fields.append(FieldDescriptor(name: "APP0 Marker", offset: 2, size: 2, type: .magic, endianness: .big))
        fields.append(FieldDescriptor(name: "APP0 Length", offset: 4, size: 2, type: .uint16, endianness: .big))
        fields.append(FieldDescriptor(name: "Identifier", offset: 6, size: 5, type: .ascii, endianness: .big))
        fields.append(FieldDescriptor(name: "Version Major", offset: 11, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "Version Minor", offset: 12, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "Density Units", offset: 13, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "X Density", offset: 14, size: 2, type: .uint16, endianness: .big))
        fields.append(FieldDescriptor(name: "Y Density", offset: 16, size: 2, type: .uint16, endianness: .big))

        return fields
    }

    /// Map JFIF density units byte to a human-readable name.
    static func densityUnitsName(_ value: UInt8) -> String {
        switch value {
        case 0: return "No units (aspect ratio)"
        case 1: return "Pixels/inch"
        case 2: return "Pixels/cm"
        default: return "Unknown (\(value))"
        }
    }
}

// MARK: - ELF interpreter

struct ELFInterpreter: FileFormatInterpreter {

    static func fields(for data: Data) -> [FieldDescriptor] {
        var fields: [FieldDescriptor] = []

        // ELF magic
        fields.append(FieldDescriptor(name: "ELF Magic", offset: 0, size: 4, type: .magic, endianness: .big))

        guard data.count >= 20 else { return fields }

        fields.append(FieldDescriptor(name: "Class", offset: 4, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "Data Encoding", offset: 5, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "ELF Version", offset: 6, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "OS/ABI", offset: 7, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "ABI Version", offset: 8, size: 1, type: .uint8, endianness: .big))
        fields.append(FieldDescriptor(name: "Padding", offset: 9, size: 7, type: .bytes, endianness: .big))

        // e_type and e_machine depend on the file's own endianness (byte 5)
        let fileEndianness: Endianness = (data.count > 5 && data[data.startIndex + 5] == 1) ? .little : .big
        fields.append(FieldDescriptor(name: "Type", offset: 16, size: 2, type: .uint16, endianness: fileEndianness))
        fields.append(FieldDescriptor(name: "Machine", offset: 18, size: 2, type: .uint16, endianness: fileEndianness))

        return fields
    }

    /// Map ELF class byte to a human-readable name.
    static func className(_ value: UInt8) -> String {
        switch value {
        case 1: return "32-bit"
        case 2: return "64-bit"
        default: return "Unknown (\(value))"
        }
    }

    /// Map ELF data encoding byte.
    static func dataEncodingName(_ value: UInt8) -> String {
        switch value {
        case 1: return "Little-endian"
        case 2: return "Big-endian"
        default: return "Unknown (\(value))"
        }
    }

    /// Map ELF OS/ABI byte.
    static func osABIName(_ value: UInt8) -> String {
        switch value {
        case 0: return "System V"
        case 1: return "HP-UX"
        case 2: return "NetBSD"
        case 3: return "Linux"
        case 6: return "Solaris"
        case 9: return "FreeBSD"
        case 12: return "OpenBSD"
        default: return "Other (\(value))"
        }
    }

    /// Map ELF type field.
    static func typeName(_ value: UInt16) -> String {
        switch value {
        case 0: return "None"
        case 1: return "Relocatable"
        case 2: return "Executable"
        case 3: return "Shared object"
        case 4: return "Core"
        default: return "Unknown (\(value))"
        }
    }

    /// Map ELF machine field.
    static func machineName(_ value: UInt16) -> String {
        switch value {
        case 0x03: return "x86"
        case 0x08: return "MIPS"
        case 0x14: return "PowerPC"
        case 0x28: return "ARM"
        case 0x3E: return "x86-64"
        case 0xB7: return "AArch64"
        case 0xF3: return "RISC-V"
        default: return "Other (0x\(String(format: "%X", value)))"
        }
    }
}

// MARK: - File annotator

/// Uses `MagicBytes.detect()` to pick the right `FileFormatInterpreter` and
/// returns decoded `[FieldValue]` for the file's header.
enum FileAnnotator {

    /// Annotate known header fields in `data`.
    static func annotate(data: Data) -> [FieldValue] {
        guard let signature = MagicBytes.detect(from: data) else { return [] }

        let descriptors: [FieldDescriptor]
        switch signature.name {
        case "PNG Image":
            descriptors = PNGInterpreter.fields(for: data)
        case "JPEG Image":
            descriptors = JPEGInterpreter.fields(for: data)
        case "ELF Executable":
            descriptors = ELFInterpreter.fields(for: data)
        default:
            return []
        }

        return descriptors.compactMap { desc in
            guard desc.offset + desc.size <= data.count else { return nil }
            let start = data.startIndex + desc.offset
            let end = start + desc.size
            let rawBytes = Data(data[start..<end])

            var display = ByteDecoder.decode(field: desc, from: data)

            // Apply format-specific enrichment
            display = enrich(field: desc, rawDisplay: display, data: data, formatName: signature.name)

            return FieldValue(descriptor: desc, rawBytes: rawBytes, displayValue: display)
        }
    }

    /// Add human-friendly names for well-known enum fields (color type, density units, etc.)
    private static func enrich(field: FieldDescriptor, rawDisplay: String, data: Data, formatName: String) -> String {
        switch (formatName, field.name) {
        case ("PNG Image", "Color Type"):
            if let v = ByteDecoder.readUInt8(from: data, at: field.offset) {
                return "\(v) (\(PNGInterpreter.colorTypeName(v)))"
            }
        case ("JPEG Image", "Density Units"):
            if let v = ByteDecoder.readUInt8(from: data, at: field.offset) {
                return "\(v) (\(JPEGInterpreter.densityUnitsName(v)))"
            }
        case ("ELF Executable", "Class"):
            if let v = ByteDecoder.readUInt8(from: data, at: field.offset) {
                return ELFInterpreter.className(v)
            }
        case ("ELF Executable", "Data Encoding"):
            if let v = ByteDecoder.readUInt8(from: data, at: field.offset) {
                return ELFInterpreter.dataEncodingName(v)
            }
        case ("ELF Executable", "OS/ABI"):
            if let v = ByteDecoder.readUInt8(from: data, at: field.offset) {
                return ELFInterpreter.osABIName(v)
            }
        case ("ELF Executable", "Type"):
            if let v = ByteDecoder.readUInt16(from: data, at: field.offset, endianness: field.endianness) {
                return ELFInterpreter.typeName(v)
            }
        case ("ELF Executable", "Machine"):
            if let v = ByteDecoder.readUInt16(from: data, at: field.offset, endianness: field.endianness) {
                return ELFInterpreter.machineName(v)
            }
        default:
            break
        }
        return rawDisplay
    }

    /// Look up the annotation for a specific byte offset, if any.
    /// Returns `(fieldName, displayValue)` for tooltip use.
    static func tooltip(for byteOffset: Int, in annotations: [FieldValue]) -> String? {
        for fv in annotations {
            let start = fv.descriptor.offset
            let end = start + fv.descriptor.size
            if byteOffset >= start && byteOffset < end {
                return "\(fv.descriptor.name): \(fv.displayValue)"
            }
        }
        return nil
    }
}
