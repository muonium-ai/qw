//
//  FormatDatabase.swift
//  qw
//
//  Loads binary format definitions (signatures, sections, fields) from an
//  SQLite database, enabling signature updates without recompilation.
//  Ticket: T-000031
//

import Foundation
import SQLite3

// MARK: - Database signature (mirrors FileSignature but includes DB id)

/// A file signature loaded from the format database, including its row id
/// so that related sections and fields can be queried.
struct DBFileSignature {
    let id: Int
    let name: String
    let description: String
    let category: String
    let matchedRange: Range<Int>
}

// MARK: - FormatDatabase

/// Reads binary-format definitions from a SQLite database.  Tries an optional
/// user-supplied path first (for updates), then falls back to the app bundle.
final class FormatDatabase {

    // MARK: Singleton

    static let shared: FormatDatabase = {
        let bundlePath = Bundle.main.path(forResource: "formats", ofType: "db")

        // User-updatable copy in Application Support
        let userPath: String? = {
            guard let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else { return nil }
            let p = support.appendingPathComponent("qw/formats.db").path
            return FileManager.default.fileExists(atPath: p) ? p : nil
        }()

        return FormatDatabase(bundlePath: bundlePath, userPath: userPath)
    }()

    // MARK: Private state

    private var db: OpaquePointer?

    // MARK: Init

    init(bundlePath: String?, userPath: String?) {
        // Try user path first, then bundle path.
        let pathToOpen = userPath ?? bundlePath
        guard let path = pathToOpen else {
            NSLog("[FormatDatabase] No database file found; database features disabled.")
            return
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        if rc != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            NSLog("[FormatDatabase] Failed to open \(path): \(msg)")
            sqlite3_close(handle)
            return
        }
        db = handle
    }

    deinit {
        if let db = db { sqlite3_close(db) }
    }

    /// Whether a valid database is currently open.
    var isAvailable: Bool { db != nil }

    // MARK: - Signature detection

    /// Query the database for a matching signature in `data`.
    /// Checks each signature's `magic_bytes` at `magic_offset`, ordered by
    /// priority (descending) then magic_bytes length (descending) so the most
    /// specific match wins.
    func detectSignature(from data: Data) -> DBFileSignature? {
        guard let db = db else { return nil }
        guard !data.isEmpty else { return nil }

        let sql = """
            SELECT id, name, description, category, magic_bytes, magic_offset, magic_mask
            FROM signatures
            ORDER BY priority DESC, LENGTH(magic_bytes) DESC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowId = Int(sqlite3_column_int64(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let desc = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let cat = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""

            let blobPtr = sqlite3_column_blob(stmt, 4)
            let blobLen = Int(sqlite3_column_bytes(stmt, 4))
            guard let ptr = blobPtr, blobLen > 0 else { continue }
            let magicBytes = Data(bytes: ptr, count: blobLen)

            let offset = Int(sqlite3_column_int(stmt, 5))

            // Optional mask
            let maskPtr = sqlite3_column_blob(stmt, 6)
            let maskLen = Int(sqlite3_column_bytes(stmt, 6))
            let mask: Data? = (maskPtr != nil && maskLen == blobLen)
                ? Data(bytes: maskPtr!, count: maskLen)
                : nil

            let endIndex = offset + magicBytes.count
            guard data.count >= endIndex else { continue }

            var matches = true
            for i in 0..<magicBytes.count {
                let dataByte = data[data.startIndex + offset + i]
                let sigByte = magicBytes[magicBytes.startIndex + i]
                if let mask = mask {
                    if (dataByte & mask[mask.startIndex + i]) != (sigByte & mask[mask.startIndex + i]) {
                        matches = false
                        break
                    }
                } else {
                    if dataByte != sigByte {
                        matches = false
                        break
                    }
                }
            }

            if matches {
                return DBFileSignature(
                    id: rowId,
                    name: name,
                    description: desc,
                    category: cat,
                    matchedRange: offset..<endIndex
                )
            }
        }

        return nil
    }

    // MARK: - Section loading

    /// Load static section definitions for a given signature id.
    /// Only evaluates integer-literal offset/length expressions for now.
    func loadSections(signatureId: Int, data: Data) -> [FileSection] {
        guard let db = db else { return [] }

        let sql = """
            SELECT name, kind, description, offset_expr, length_expr, color
            FROM sections
            WHERE signature_id = ?
            ORDER BY CAST(offset_expr AS INTEGER)
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(signatureId))

        var result: [FileSection] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            let kindStr = String(cString: sqlite3_column_text(stmt, 1))
            let desc = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let offsetExpr = String(cString: sqlite3_column_text(stmt, 3))
            let lengthExpr = String(cString: sqlite3_column_text(stmt, 4))

            // Parse integer literals only (future: expression evaluator)
            guard let off = Int(offsetExpr), let len = Int(lengthExpr) else { continue }
            let end = min(off + len, data.count)
            guard off < data.count else { continue }

            let kind = sectionKind(from: kindStr)
            result.append(FileSection(
                name: name,
                range: off..<end,
                kind: kind,
                description: desc
            ))
        }

        return result
    }

    // MARK: - Field loading

    /// Load field definitions for a given signature id and decode values from `data`.
    func loadFields(signatureId: Int, data: Data) -> [FieldValue] {
        guard let db = db else { return [] }

        let sql = """
            SELECT name, offset, size, type, endianness, display_format, value_map, section_name
            FROM fields
            WHERE signature_id = ?
            ORDER BY offset
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(signatureId))

        var result: [FieldValue] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            let offset = Int(sqlite3_column_int(stmt, 1))
            let size = Int(sqlite3_column_int(stmt, 2))
            let typeStr = String(cString: sqlite3_column_text(stmt, 3))
            let endStr = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "big"
            let displayFmt = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            let valueMapJSON = sqlite3_column_text(stmt, 6).map { String(cString: $0) }

            guard offset + size <= data.count else { continue }

            let fieldType = self.fieldType(from: typeStr)
            let endianness: Endianness = (endStr == "little") ? .little : .big

            let descriptor = FieldDescriptor(
                name: name,
                offset: offset,
                size: size,
                type: fieldType,
                endianness: endianness
            )

            let start = data.startIndex + offset
            let end = start + size
            let rawBytes = Data(data[start..<end])

            var display = decodeField(descriptor: descriptor, data: data)

            // Apply value_map enrichment
            if let json = valueMapJSON, let map = parseValueMap(json) {
                display = applyValueMap(map: map, rawDisplay: display, descriptor: descriptor, data: data)
            }

            // Apply display_format override
            if let fmt = displayFmt {
                display = applyDisplayFormat(fmt, descriptor: descriptor, data: data, fallback: display)
            }

            result.append(FieldValue(
                descriptor: descriptor,
                rawBytes: rawBytes,
                displayValue: display
            ))
        }

        return result
    }

    // MARK: - Private helpers

    private func sectionKind(from str: String) -> SectionKind {
        switch str.lowercased() {
        case "signature": return .signature
        case "header":    return .header
        case "metadata":  return .metadata
        case "data":      return .data
        case "footer":    return .footer
        case "chunk":     return .chunk
        default:          return .chunk
        }
    }

    private func fieldType(from str: String) -> FieldType {
        switch str.lowercased() {
        case "uint8":   return .uint8
        case "uint16":  return .uint16
        case "uint32":  return .uint32
        case "uint64":  return .uint64
        case "int8":    return .int8
        case "int16":   return .int16
        case "int32":   return .int32
        case "int64":   return .int64
        case "float32": return .float32
        case "float64": return .float64
        case "ascii":   return .ascii
        case "bytes":   return .bytes
        case "magic":   return .magic
        default:        return .bytes
        }
    }

    /// Decode a field's value to a display string, using the same logic as
    /// the hardcoded ByteDecoder in FileFormatInterpreter.swift.
    private func decodeField(descriptor: FieldDescriptor, data: Data) -> String {
        let offset = descriptor.offset
        guard offset + descriptor.size <= data.count else { return "\u{2014}" }
        let base = data.startIndex + offset

        switch descriptor.type {
        case .uint8:
            return "\(data[base])"
        case .uint16:
            let v = readUInt16(data, at: offset, endianness: descriptor.endianness)
            return "\(v)"
        case .uint32:
            let v = readUInt32(data, at: offset, endianness: descriptor.endianness)
            return "\(v)"
        case .uint64:
            let v = readUInt64(data, at: offset, endianness: descriptor.endianness)
            return "\(v)"
        case .int8:
            return "\(Int8(bitPattern: data[base]))"
        case .int16:
            let v = readUInt16(data, at: offset, endianness: descriptor.endianness)
            return "\(Int16(bitPattern: v))"
        case .int32:
            let v = readUInt32(data, at: offset, endianness: descriptor.endianness)
            return "\(Int32(bitPattern: v))"
        case .int64:
            let v = readUInt64(data, at: offset, endianness: descriptor.endianness)
            return "\(Int64(bitPattern: v))"
        case .float32:
            let bits = readUInt32(data, at: offset, endianness: descriptor.endianness)
            let value = Float(bitPattern: bits)
            return value.isNaN ? "NaN" : "\(value)"
        case .float64:
            let bits = readUInt64(data, at: offset, endianness: descriptor.endianness)
            let value = Double(bitPattern: bits)
            return value.isNaN ? "NaN" : "\(value)"
        case .ascii:
            let slice = data[base..<(base + descriptor.size)]
            let trimmed = slice.prefix(while: { $0 != 0 })
            return String(data: Data(trimmed), encoding: .ascii) ?? "\u{2014}"
        case .bytes, .magic:
            let slice = data[base..<(base + descriptor.size)]
            return slice.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
    }

    private func readUInt16(_ data: Data, at offset: Int, endianness: Endianness) -> UInt16 {
        let base = data.startIndex + offset
        if endianness == .little {
            return UInt16(data[base]) | UInt16(data[base + 1]) << 8
        } else {
            return UInt16(data[base]) << 8 | UInt16(data[base + 1])
        }
    }

    private func readUInt32(_ data: Data, at offset: Int, endianness: Endianness) -> UInt32 {
        let base = data.startIndex + offset
        if endianness == .little {
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

    private func readUInt64(_ data: Data, at offset: Int, endianness: Endianness) -> UInt64 {
        let base = data.startIndex + offset
        if endianness == .little {
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

    private func parseValueMap(_ json: String) -> [String: String]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return nil }
        return obj
    }

    /// Apply a value_map: look up the raw numeric value as a string key.
    private func applyValueMap(map: [String: String], rawDisplay: String, descriptor: FieldDescriptor, data: Data) -> String {
        // The raw numeric value (before any enrichment) is in rawDisplay
        let key = rawDisplay.trimmingCharacters(in: .whitespaces)
        if let mapped = map[key] {
            return "\(key) (\(mapped))"
        }
        return rawDisplay
    }

    /// Apply display_format override (hex, binary, etc.) for simple integer types.
    private func applyDisplayFormat(_ fmt: String, descriptor: FieldDescriptor, data: Data, fallback: String) -> String {
        // Only override for hex display on integer types when value_map didn't already enrich
        if fmt == "hex" && fallback.contains("(") {
            return fallback  // already enriched
        }
        // For "hex" on magic/bytes types the default is already hex, so no change needed
        // For other cases, keep the fallback
        return fallback
    }
}
