//
//  HexView.swift
//  qw
//
//  Read-only hex viewer that displays file contents in canonical hex dump format.
//  Ticket: T-000019
//

import SwiftUI

/// A row of hex dump output: offset, 16 bytes of hex, and ASCII representation.
private struct HexRow: Identifiable {
    let id: Int // row index
    let offset: Int
    let bytes: [UInt8]
}

/// Read-only hex viewer displaying Data in canonical hex dump format.
///
/// Layout per row:
///   `00000010  48 65 6c 6c 6f 20 57 6f  72 6c 64 21 0a 00 00 00  |Hello World!....|`
///
/// - Three columns: offset gutter, hex bytes (16 per row with wider gap after byte 8), ASCII sidebar.
/// - Non-printable bytes render as `.` in the ASCII column.
/// - Null bytes are dimmed, high bytes (>127) use the accent color, printable ASCII uses the default color.
/// - Alternating row backgrounds for readability.
/// - Status bar showing total file size.
struct HexView: View {
    let data: Data

    // MARK: - Computed

    private var rows: [HexRow] {
        let bytes = [UInt8](data)
        let totalRows = max((bytes.count + 15) / 16, 0)
        return (0..<totalRows).map { index in
            let start = index * 16
            let end = min(start + 16, bytes.count)
            return HexRow(id: index, offset: start, bytes: Array(bytes[start..<end]))
        }
    }

    private var fileSizeDescription: String {
        let count = data.count
        if count == 0 {
            return "0 bytes"
        } else if count == 1 {
            return "1 byte"
        } else if count < 1024 {
            return "\(count) bytes"
        } else if count < 1024 * 1024 {
            return String(format: "%.1f KB (%d bytes)", Double(count) / 1024.0, count)
        } else {
            return String(format: "%.1f MB (%d bytes)", Double(count) / (1024.0 * 1024.0), count)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if data.isEmpty {
                emptyView
            } else {
                hexContent
            }
            statusBar
        }
    }

    // MARK: - Subviews

    private var emptyView: some View {
        VStack {
            Spacer()
            Text("Empty file")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hexContent: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    hexRowView(row)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(row.id.isMultiple(of: 2) ? Color.clear : alternateRowBackground)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(fileSizeDescription)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color(uiColor: .secondarySystemBackground)
            #endif
        }
    }

    // MARK: - Row rendering

    private func hexRowView(_ row: HexRow) -> some View {
        HStack(spacing: 0) {
            // Offset gutter
            Text(String(format: "%08x", row.offset))
                .foregroundStyle(.secondary)

            Text("  ")

            // Hex bytes — first 8
            ForEach(0..<8, id: \.self) { i in
                if i < row.bytes.count {
                    Text(String(format: "%02x ", row.bytes[i]))
                        .foregroundStyle(byteColor(row.bytes[i]))
                } else {
                    Text("   ")
                }
            }

            // Wider gap between byte 8 and 9
            Text(" ")

            // Hex bytes — second 8
            ForEach(8..<16, id: \.self) { i in
                if i < row.bytes.count {
                    Text(String(format: "%02x ", row.bytes[i]))
                        .foregroundStyle(byteColor(row.bytes[i]))
                } else {
                    Text("   ")
                }
            }

            Text(" ")

            // ASCII sidebar
            Text("|")
                .foregroundStyle(.secondary)
            ForEach(0..<row.bytes.count, id: \.self) { i in
                Text(asciiCharacter(row.bytes[i]))
                    .foregroundStyle(byteColor(row.bytes[i]))
            }
            Text("|")
                .foregroundStyle(.secondary)
        }
        .font(.system(.body, design: .monospaced))
    }

    // MARK: - Helpers

    /// Returns the printable ASCII character for a byte, or `.` for non-printable bytes.
    private func asciiCharacter(_ byte: UInt8) -> String {
        if byte >= 0x20 && byte <= 0x7E {
            return String(UnicodeScalar(byte))
        }
        return "."
    }

    /// Color-codes a byte value:
    /// - Null (0x00): dimmed
    /// - Printable ASCII (0x20-0x7E): default foreground
    /// - High bytes (>127): accent color
    /// - Other non-printable: secondary
    private func byteColor(_ byte: UInt8) -> Color {
        if byte == 0x00 {
            return .secondary.opacity(0.5)
        } else if byte > 0x7F {
            return .accentColor
        } else if byte >= 0x20 && byte <= 0x7E {
            #if os(macOS)
            return Color(nsColor: .labelColor)
            #else
            return Color(uiColor: .label)
            #endif
        } else {
            return .secondary
        }
    }

    private var alternateRowBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor).opacity(0.5)
        #else
        Color(uiColor: .secondarySystemBackground).opacity(0.5)
        #endif
    }
}

// MARK: - Preview

#Preview("Hex View — sample data") {
    HexView(data: "Hello, World! This is a hex viewer test with enough text to span multiple rows.\n\0\u{80}\u{FF}".data(using: .utf8)!)
}

#Preview("Hex View — empty") {
    HexView(data: Data())
}
