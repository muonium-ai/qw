//
//  FormatMismatchDetector.swift
//  qw
//
//  Detects mismatches between file extension and magic-bytes-detected content type.
//  Critical mismatches (e.g. executable disguised as image) prevent auto-routing.
//  Ticket: T-000063
//

import Foundation
import os

/// Compares a file's extension against its detected magic-bytes content type
/// and reports mismatches with appropriate severity.
enum FormatMismatchDetector {

    // MARK: - Types

    /// Severity of a detected mismatch.
    enum Severity: Comparable {
        /// Extension claims non-executable but content is executable — possible attack.
        case critical
        /// Extension and content disagree but neither is executable.
        case warning
        /// Unknown extension or ambiguous detection.
        case info
    }

    /// Result of a mismatch check.
    struct MismatchResult {
        let severity: Severity
        let extensionType: String
        let detectedType: String
        let message: String
    }

    // MARK: - Extension → category mapping

    /// Maps common file extensions (lowercased, without dot) to expected content categories.
    private static let extensionCategories: [String: String] = {
        var map = [String: String]()
        let imageExts = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "ico", "heic", "heif", "svg", "avif"]
        let videoExts = ["mp4", "avi", "mkv", "webm", "mov", "flv", "wmv", "mpeg", "mpg", "m4v", "3gp", "ogv"]
        let audioExts = ["mp3", "wav", "flac", "ogg", "aac", "m4a", "aiff", "aif", "midi", "mid", "opus", "wma", "oga"]
        let documentExts = ["pdf", "xml", "json", "html", "htm", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtf", "odt", "ods"]
        let executableExts = ["exe", "app", "wasm", "jar", "sh", "bat", "cmd", "com", "msi", "dll", "so", "dylib", "elf", "bin", "run"]
        let archiveExts = ["zip", "gz", "bz2", "xz", "tar", "rar", "7z", "lz", "lzma", "zst", "cab", "dmg", "iso"]

        for ext in imageExts      { map[ext] = "image" }
        for ext in videoExts      { map[ext] = "video" }
        for ext in audioExts      { map[ext] = "audio" }
        for ext in documentExts   { map[ext] = "document" }
        for ext in executableExts { map[ext] = "executable" }
        for ext in archiveExts    { map[ext] = "archive" }
        return map
    }()

    // MARK: - Format name → category mapping (hardcoded registry fallback)

    /// Infers a category from the detected format name when the DB category is
    /// unavailable (i.e. the match came from the hardcoded MagicBytes registry).
    private static func inferCategory(fromFormatName name: String) -> String? {
        let lower = name.lowercased()

        if isExecutableFormat(name: name) { return "executable" }

        let imageKeywords  = ["png", "jpeg", "gif", "bmp", "tiff", "webp", "ico", "heic", "image"]
        let videoKeywords  = ["mp4", "video", "avi", "mkv", "webm", "mov", "flv", "mpeg", "matroska"]
        let audioKeywords  = ["wav", "riff", "mp3", "flac", "ogg", "aac", "m4a", "aiff", "midi", "audio", "opus"]
        let documentKeywords = ["pdf", "xml", "json", "document", "sqlite"]
        let archiveKeywords  = ["zip", "gzip", "bzip", "bz2", "xz", "tar", "rar", "7z", "archive", "compressed"]

        if imageKeywords.contains(where:    { lower.contains($0) }) { return "image" }
        if videoKeywords.contains(where:    { lower.contains($0) }) { return "video" }
        if audioKeywords.contains(where:    { lower.contains($0) }) { return "audio" }
        if documentKeywords.contains(where: { lower.contains($0) }) { return "document" }
        if archiveKeywords.contains(where:  { lower.contains($0) }) { return "archive" }

        return nil
    }

    // MARK: - Executable detection

    /// Returns `true` when the detected format name indicates a native executable
    /// or binary module (Mach-O, ELF, PE, WebAssembly).
    static func isExecutableFormat(name: String) -> Bool {
        let lower = name.lowercased()
        let executableKeywords = ["mach-o", "elf", "windows pe", "pe/exe", "webassembly"]
        return executableKeywords.contains(where: { lower.contains($0) })
    }

    // MARK: - Main check

    /// Compare a file's extension against the magic-bytes-detected format.
    ///
    /// - Parameters:
    ///   - fileURL: The file URL (used for its extension). `nil` for untitled documents.
    ///   - detectedFormatName: Human-readable name from `MagicBytes.detect()` or the DB.
    ///   - detectedCategory: The `category` field from `DBFileSignature`, or `nil` if the
    ///     match came from the hardcoded registry.
    /// - Returns: A `MismatchResult` if the extension and content disagree, otherwise `nil`.
    static func check(fileURL: URL?, detectedFormatName: String?, detectedCategory: String?) -> MismatchResult? {
        guard let url = fileURL else { return nil }

        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }

        guard let formatName = detectedFormatName, !formatName.isEmpty else { return nil }

        // Determine the expected category from the file extension
        guard let expectedCategory = extensionCategories[ext] else {
            // Unknown extension — nothing to compare
            return nil
        }

        // Determine the actual category from detection
        let actualCategory: String
        if let dbCategory = detectedCategory, !dbCategory.isEmpty {
            actualCategory = dbCategory.lowercased()
        } else if let inferred = inferCategory(fromFormatName: formatName) {
            actualCategory = inferred
        } else {
            // Cannot determine content category — log as info
            let result = MismatchResult(
                severity: .info,
                extensionType: expectedCategory,
                detectedType: "unknown",
                message: "Extension suggests \(expectedCategory), but content type (\(formatName)) could not be categorized."
            )
            logMismatch(result, fileURL: url)
            return result
        }

        // Check for match — some flexibility for related categories
        if categoriesMatch(expected: expectedCategory, actual: actualCategory) {
            return nil  // No mismatch
        }

        // Mismatch detected — determine severity
        let severity: Severity
        let message: String

        if isExecutableFormat(name: formatName) && expectedCategory != "executable" {
            // CRITICAL: Content is executable but extension claims otherwise
            severity = .critical
            message = "SECURITY WARNING: File \"\(url.lastPathComponent)\" has a .\(ext) extension (\(expectedCategory)) but contains executable content (\(formatName)). This file may be malicious."
        } else if expectedCategory == "executable" && actualCategory != "executable" {
            // Extension says executable but content is not — less dangerous, still a warning
            severity = .warning
            message = "File \"\(url.lastPathComponent)\" has an executable extension (.\(ext)) but content is \(formatName) (\(actualCategory))."
        } else {
            // General category mismatch
            severity = .warning
            message = "File extension mismatch: \"\(url.lastPathComponent)\" has a .\(ext) extension (\(expectedCategory)) but content is \(formatName) (\(actualCategory))."
        }

        let result = MismatchResult(
            severity: severity,
            extensionType: expectedCategory,
            detectedType: actualCategory,
            message: message
        )
        logMismatch(result, fileURL: url)
        return result
    }

    // MARK: - Private helpers

    /// Some category pairs are compatible (e.g. "proprietary" can match many extensions).
    private static func categoriesMatch(expected: String, actual: String) -> Bool {
        if expected == actual { return true }

        // The "proprietary" category in the DB can legitimately match many extension types
        // (e.g. .psd is proprietary but has image extension expectations)
        if actual == "proprietary" { return true }

        // "3d-open" formats don't have standard extensions in our map, so skip
        if actual == "3d-open" { return true }

        return false
    }

    // MARK: - Logging

    private static let logger = Logger(subsystem: "com.muonium.qw", category: "formats")

    private static func logMismatch(_ result: MismatchResult, fileURL: URL) {
        let ext = fileURL.pathExtension
        switch result.severity {
        case .critical:
            logger.warning("[formats] CRITICAL mismatch: .\(ext, privacy: .public) extension=\(result.extensionType, privacy: .public) content=\(result.detectedType, privacy: .public) — \(result.message, privacy: .public)")
        case .warning:
            logger.notice("[formats] Mismatch: .\(ext, privacy: .public) extension=\(result.extensionType, privacy: .public) content=\(result.detectedType, privacy: .public) — \(result.message, privacy: .public)")
        case .info:
            logger.info("[formats] Info: .\(ext, privacy: .public) extension=\(result.extensionType, privacy: .public) content=\(result.detectedType, privacy: .public) — \(result.message, privacy: .public)")
        }
    }
}
