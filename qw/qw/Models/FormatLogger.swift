//
//  FormatLogger.swift
//  qw
//
//  Structured logging for file format detection and viewer open/failure events.
//  Ticket: T-000054
//

import Foundation
import os

/// Lightweight logging helper for file format open/failure events.
enum FormatLogger {

    private static let logger = Logger(subsystem: "com.muonium.qw", category: "formats")

    /// Log a failure to open a file in a given viewer mode.
    /// - Parameters:
    ///   - fileURL: The file URL (used for extension); nil for untitled documents.
    ///   - formatName: Human-readable format name from magic bytes (e.g. "PNG Image").
    ///   - mode: The viewer mode attempted: "image", "video", "audio", "hex", or "text".
    ///   - error: A description of what went wrong.
    static func logOpenFailure(fileURL: URL?, formatName: String?, mode: String, error: String) {
        let ext = fileURL?.pathExtension ?? "unknown"
        let fmt = formatName ?? "unknown"
        logger.error("[formats] Failed to open .\(ext, privacy: .public) (\(fmt, privacy: .public)) in \(mode, privacy: .public) mode: \(error, privacy: .public)")
    }

    /// Log a successful file open in a given viewer mode.
    /// - Parameters:
    ///   - fileURL: The file URL (used for extension); nil for untitled documents.
    ///   - formatName: Human-readable format name from magic bytes.
    ///   - mode: The viewer mode: "image", "video", "audio", "hex", or "text".
    static func logOpenSuccess(fileURL: URL?, formatName: String?, mode: String) {
        let ext = fileURL?.pathExtension ?? "unknown"
        let fmt = formatName ?? "unknown"
        logger.info("[formats] Opened .\(ext, privacy: .public) (\(fmt, privacy: .public)) in \(mode, privacy: .public) mode")
    }
}
