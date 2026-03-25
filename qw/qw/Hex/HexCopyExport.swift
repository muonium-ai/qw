//
//  HexCopyExport.swift
//  qw
//
//  Copy/export hex selections in various formats.
//  Ticket: T-000024
//

import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Output formats for copying hex data to the clipboard.
enum HexCopyFormat: String, CaseIterable, Identifiable {
    case hexString   = "Hex String"
    case cArray      = "C Array"
    case swiftArray  = "Swift Array"
    case rawBytes    = "Raw Bytes"
    case hexDump     = "Hex Dump"

    var id: String { rawValue }
}

/// Formats binary data into various textual representations for clipboard export.
struct HexFormatter {

    // MARK: - Public formatting

    /// Formats data as a space-separated hex string, e.g. `"FF D8 FF E0 00 10"`.
    static func formatAsHexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Formats data as a C-style array literal, e.g. `"{ 0xFF, 0xD8, 0xFF, 0xE0 }"`.
    static func formatAsCArray(_ data: Data) -> String {
        let elements = data.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
        return "{ \(elements) }"
    }

    /// Formats data as a Swift array literal, e.g. `"[0xFF, 0xD8, 0xFF, 0xE0]"`.
    static func formatAsSwiftArray(_ data: Data) -> String {
        let elements = data.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
        return "[\(elements)]"
    }

    /// Formats data as raw bytes (no separators), e.g. `"FFD8FFE00010"`.
    static func formatAsRawBytes(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    /// Formats data as a canonical hex dump with offset | hex | ASCII columns.
    ///
    /// Example row:
    /// ```
    /// 00000010  48 65 6c 6c 6f 20 57 6f  72 6c 64 21 0a 00 00 00  |Hello World!....|
    /// ```
    static func formatAsHexDump(_ data: Data, startOffset: Int = 0) -> String {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return "" }

        let totalRows = (bytes.count + 15) / 16
        var lines: [String] = []
        lines.reserveCapacity(totalRows)

        for rowIndex in 0..<totalRows {
            let rowStart = rowIndex * 16
            let rowEnd = min(rowStart + 16, bytes.count)
            let rowBytes = Array(bytes[rowStart..<rowEnd])

            // Offset
            let offset = String(format: "%08x", startOffset + rowStart)

            // Hex columns — first 8
            var hexPart = ""
            for i in 0..<8 {
                if i < rowBytes.count {
                    hexPart += String(format: "%02x ", rowBytes[i])
                } else {
                    hexPart += "   "
                }
            }
            hexPart += " "
            // Hex columns — second 8
            for i in 8..<16 {
                if i < rowBytes.count {
                    hexPart += String(format: "%02x ", rowBytes[i])
                } else {
                    hexPart += "   "
                }
            }

            // ASCII sidebar
            let ascii = rowBytes.map { byte -> String in
                if byte >= 0x20 && byte <= 0x7E {
                    return String(UnicodeScalar(byte))
                }
                return "."
            }.joined()

            lines.append("\(offset)  \(hexPart) |\(ascii)|")
        }
        return lines.joined(separator: "\n")
    }

    /// Formats data using the specified format.
    static func format(_ data: Data, as format: HexCopyFormat, startOffset: Int = 0) -> String {
        switch format {
        case .hexString:  return formatAsHexString(data)
        case .cArray:     return formatAsCArray(data)
        case .swiftArray: return formatAsSwiftArray(data)
        case .rawBytes:   return formatAsRawBytes(data)
        case .hexDump:    return formatAsHexDump(data, startOffset: startOffset)
        }
    }

    /// Copies formatted data to the system clipboard.
    static func copyToClipboard(_ data: Data, format: HexCopyFormat, startOffset: Int = 0) {
        let text = Self.format(data, as: format, startOffset: startOffset)
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}
