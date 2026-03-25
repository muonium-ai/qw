//
//  MagicBytes.swift
//  qw
//
//  Detects file types from magic byte signatures in binary data.
//  Ticket: T-000025
//

import Foundation

/// Describes a matched file signature detected from magic bytes.
struct FileSignature {
    /// Human-readable name, e.g. "PNG Image".
    let name: String
    /// Additional detail about the format.
    let description: String
    /// The byte range in the data that matched the signature.
    let matchedRange: Range<Int>
}

/// Registry of known file signatures and a detector that checks binary data
/// against them.
enum MagicBytes {

    // MARK: - Signature entry (private)

    /// A single entry in the signature registry.
    private struct Entry {
        let bytes: [UInt8]
        let offset: Int          // where in the data to start matching
        let name: String
        let description: String
    }

    // MARK: - Registry

    /// Known file signatures ordered from longest/most-specific to shortest so
    /// that the first match wins when multiple prefixes overlap (e.g. PNG's
    /// 8-byte header beats a shorter prefix).
    private static let registry: [Entry] = [
        // Images
        Entry(bytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
              offset: 0, name: "PNG Image",
              description: "Portable Network Graphics image"),
        Entry(bytes: [0xFF, 0xD8, 0xFF],
              offset: 0, name: "JPEG Image",
              description: "JPEG/JFIF image"),
        Entry(bytes: [0x47, 0x49, 0x46, 0x38],
              offset: 0, name: "GIF Image",
              description: "Graphics Interchange Format image"),

        // Documents
        Entry(bytes: [0x25, 0x50, 0x44, 0x46],
              offset: 0, name: "PDF Document",
              description: "Portable Document Format"),

        // Archives
        Entry(bytes: [0x50, 0x4B, 0x03, 0x04],
              offset: 0, name: "ZIP Archive",
              description: "ZIP compressed archive"),
        Entry(bytes: [0x50, 0x4B, 0x05, 0x06],
              offset: 0, name: "ZIP Archive (empty)",
              description: "ZIP archive (empty archive)"),
        Entry(bytes: [0x1F, 0x8B],
              offset: 0, name: "Gzip",
              description: "Gzip compressed data"),
        Entry(bytes: [0x42, 0x5A, 0x68],
              offset: 0, name: "Bzip2",
              description: "Bzip2 compressed data"),
        Entry(bytes: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00],
              offset: 0, name: "XZ",
              description: "XZ compressed data"),

        // Executables – Mach-O
        Entry(bytes: [0xCA, 0xFE, 0xBA, 0xBE],
              offset: 0, name: "Mach-O Universal Binary",
              description: "Mach-O universal (fat) binary"),
        Entry(bytes: [0xFE, 0xED, 0xFA, 0xCE],
              offset: 0, name: "Mach-O (32-bit)",
              description: "Mach-O 32-bit executable"),
        Entry(bytes: [0xFE, 0xED, 0xFA, 0xCF],
              offset: 0, name: "Mach-O (64-bit)",
              description: "Mach-O 64-bit executable"),
        Entry(bytes: [0xCF, 0xFA, 0xED, 0xFE],
              offset: 0, name: "Mach-O (64-bit, reversed)",
              description: "Mach-O 64-bit executable (little-endian)"),
        Entry(bytes: [0xCE, 0xFA, 0xED, 0xFE],
              offset: 0, name: "Mach-O (32-bit, reversed)",
              description: "Mach-O 32-bit executable (little-endian)"),

        // ELF
        Entry(bytes: [0x7F, 0x45, 0x4C, 0x46],
              offset: 0, name: "ELF Executable",
              description: "Executable and Linkable Format"),

        // Windows
        Entry(bytes: [0x4D, 0x5A],
              offset: 0, name: "Windows PE/EXE",
              description: "Windows Portable Executable"),

        // Multimedia – RIFF container (WAV, AVI, WebP, etc.)
        Entry(bytes: [0x52, 0x49, 0x46, 0x46],
              offset: 0, name: "RIFF (WAV/AVI)",
              description: "Resource Interchange File Format container"),

        // WebAssembly
        Entry(bytes: [0x00, 0x61, 0x73, 0x6D],
              offset: 0, name: "WebAssembly Binary",
              description: "WebAssembly binary module"),

        // Database
        Entry(bytes: [0x53, 0x51, 0x4C, 0x69, 0x74, 0x65],
              offset: 0, name: "SQLite",
              description: "SQLite database file"),

        // Text formats (heuristic – listed last so binary formats take priority)
        Entry(bytes: [0x3C, 0x3F, 0x78, 0x6D, 0x6C],
              offset: 0, name: "XML",
              description: "XML document"),
        Entry(bytes: [0x7B],
              offset: 0, name: "JSON (heuristic)",
              description: "Likely JSON document"),
    ]

    // MARK: - Database-backed detection

    /// Try the SQLite format database first.  Returns `nil` if the database
    /// is unavailable or contains no matching signature.
    static func detectFromDatabase(data: Data) -> FileSignature? {
        let db = FormatDatabase.shared
        guard db.isAvailable else { return nil }
        guard let dbSig = db.detectSignature(from: data) else { return nil }
        return FileSignature(
            name: dbSig.name,
            description: dbSig.description,
            matchedRange: dbSig.matchedRange
        )
    }

    // MARK: - Detection

    /// Detect the file type from magic bytes in the first 32 bytes of `data`.
    /// Tries the SQLite format database first, then falls back to the
    /// hardcoded registry.
    ///
    /// - Parameter data: The raw file data (at least a few bytes are needed).
    /// - Returns: A `FileSignature` if a known signature matches, otherwise `nil`.
    static func detect(from data: Data) -> FileSignature? {
        guard !data.isEmpty else { return nil }

        // Database-first strategy
        if let dbResult = detectFromDatabase(data: data) {
            return dbResult
        }

        let prefixLength = min(data.count, 32)
        let prefix = data.prefix(prefixLength)

        // MP4/MOV: check for "ftyp" at bytes 4-7 regardless of box size in bytes 0-3.
        if prefixLength >= 8 {
            let ftyp: [UInt8] = [0x66, 0x74, 0x79, 0x70] // "ftyp"
            let ftypMatches = ftyp.enumerated().allSatisfy { i, b in
                prefix[prefix.startIndex + 4 + i] == b
            }
            if ftypMatches {
                return FileSignature(
                    name: "MP4 Video",
                    description: "MPEG-4 Part 14 video container",
                    matchedRange: 0..<8
                )
            }
        }

        // Check the fixed-offset registry entries.
        for entry in registry {
            let endIndex = entry.offset + entry.bytes.count
            guard prefixLength >= endIndex else { continue }

            let matches = entry.bytes.enumerated().allSatisfy { i, b in
                prefix[prefix.startIndex + entry.offset + i] == b
            }
            if matches {
                return FileSignature(
                    name: entry.name,
                    description: entry.description,
                    matchedRange: entry.offset..<endIndex
                )
            }
        }

        return nil
    }
}
