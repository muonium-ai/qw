//
//  HexView.swift
//  qw
//
//  Read-only hex viewer that displays file contents in canonical hex dump format.
//  Supports byte selection and copy/export in multiple formats.
//  Ticket: T-000019, T-000023, T-000024
//

import SwiftUI

/// A row of hex dump output: offset, 16 bytes of hex, and ASCII representation.
/// Computed lazily from a Data slice — no intermediate [UInt8] array needed.
private struct HexRow: Identifiable {
    let id: Int // row index (stable ID for LazyVStack)
    let offset: Int
    let bytes: Data.SubSequence
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
/// - Click to select a byte, shift-click to extend selection.
/// - Right-click to copy selection as Hex String, C Array, Swift Array, Raw Bytes, or Hex Dump.
/// - Cmd+C copies selected bytes as a hex string.
/// - Status bar showing total file size and selection info.
///
/// **Virtual scrolling**: rows are computed lazily via `LazyVStack` and `ForEach`
/// over an index range. Only the bytes for visible rows are accessed, keeping
/// memory usage constant regardless of file size.
///
/// **Memory-mapped I/O**: use `HexView(url:)` to open large files with
/// `Data(contentsOf:options:.mappedIfSafe)` so the OS pages in only the
/// portions that are actually read.
struct HexView: View {
    let data: Data

    // MARK: - Selection state

    @State private var selectionStart: Int?
    @State private var selectionEnd: Int?

    /// The normalized (ordered) range of selected byte indices, if any.
    private var selectionRange: ClosedRange<Int>? {
        guard let s = selectionStart, let e = selectionEnd else { return nil }
        return min(s, e)...max(s, e)
    }

    /// The selected bytes as `Data`, if a selection exists.
    var selectedData: Data? {
        guard let range = selectionRange, !data.isEmpty else { return nil }
        let clamped = range.clamped(to: 0...(data.count - 1))
        guard !clamped.isEmpty else { return nil }
        let dataStart = data.startIndex + clamped.lowerBound
        let dataEnd = data.startIndex + clamped.upperBound + 1
        return Data(data[dataStart..<dataEnd])
    }

    // MARK: - Memory-mapped convenience initializer

    /// Opens a file with memory-mapped I/O (`mappedIfSafe`), suitable for
    /// files up to hundreds of megabytes without loading everything into RAM.
    /// Falls back to empty data if the file cannot be read.
    init(url: URL) {
        self.data = (try? Data(contentsOf: url, options: .mappedIfSafe)) ?? Data()
    }

    /// Standard initializer for in-memory data (small files, buffers, etc.).
    init(data: Data) {
        self.data = data
    }

    // MARK: - Computed

    /// Total number of 16-byte rows needed to display `data`.
    private var rowCount: Int {
        max((data.count + 15) / 16, 0)
    }

    /// Build a single `HexRow` on demand from the backing data.
    /// Only the 16-byte slice for this row is touched.
    private func row(at index: Int) -> HexRow {
        let start = data.startIndex + index * 16
        let end = min(start + 16, data.endIndex)
        return HexRow(id: index, offset: index * 16, bytes: data[start..<end])
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

    private var selectionDescription: String? {
        guard let range = selectionRange else { return nil }
        let count = range.count
        let label = count == 1 ? "1 byte" : "\(count) bytes"
        return "Selection: \(String(format: "0x%X", range.lowerBound))\u{2013}\(String(format: "0x%X", range.upperBound)) (\(label))"
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
        #if os(macOS)
        .onCopyCommand {
            guard let sel = selectedData else { return [] }
            let text = HexFormatter.formatAsHexString(sel)
            let item = NSItemProvider(object: text as NSString)
            return [item]
        }
        #endif
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
                ForEach(0..<rowCount, id: \.self) { index in
                    let r = row(at: index)
                    hexRowView(r)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index.isMultiple(of: 2) ? Color.clear : alternateRowBackground)
                }
            }
        }
        .contextMenu { copyContextMenu }
    }

    private var statusBar: some View {
        HStack {
            Text(fileSizeDescription)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if let sel = selectionDescription {
                Text("  |  ")
                    .foregroundStyle(.secondary)
                Text(sel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
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

    // MARK: - Context menu

    @ViewBuilder
    private var copyContextMenu: some View {
        if let sel = selectedData {
            let startOffset = selectionRange?.lowerBound ?? 0
            Button("Copy as Hex String") {
                HexFormatter.copyToClipboard(sel, format: .hexString)
            }
            Button("Copy as C Array") {
                HexFormatter.copyToClipboard(sel, format: .cArray)
            }
            Button("Copy as Swift Array") {
                HexFormatter.copyToClipboard(sel, format: .swiftArray)
            }
            Button("Copy as Raw Bytes") {
                HexFormatter.copyToClipboard(sel, format: .rawBytes)
            }
            Button("Copy as Hex Dump") {
                HexFormatter.copyToClipboard(sel, format: .hexDump, startOffset: startOffset)
            }
            Divider()
        }
        Button("Select All") {
            selectionStart = 0
            selectionEnd = data.count - 1
        }
        .disabled(data.isEmpty)
        Button("Clear Selection") {
            selectionStart = nil
            selectionEnd = nil
        }
        .disabled(selectionStart == nil)
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
                    let byte = row.bytes[row.bytes.startIndex + i]
                    hexByteView(byte: byte, absoluteIndex: row.offset + i)
                } else {
                    Text("   ")
                }
            }

            // Wider gap between byte 8 and 9
            Text(" ")

            // Hex bytes — second 8
            ForEach(8..<16, id: \.self) { i in
                if i < row.bytes.count {
                    let byte = row.bytes[row.bytes.startIndex + i]
                    hexByteView(byte: byte, absoluteIndex: row.offset + i)
                } else {
                    Text("   ")
                }
            }

            Text(" ")

            // ASCII sidebar
            Text("|")
                .foregroundStyle(.secondary)
            ForEach(0..<row.bytes.count, id: \.self) { i in
                let byte = row.bytes[row.bytes.startIndex + i]
                asciiByteView(byte: byte, absoluteIndex: row.offset + i)
            }
            Text("|")
                .foregroundStyle(.secondary)
        }
        .font(.system(.body, design: .monospaced))
    }

    /// A single hex byte cell that supports click-to-select and shift-click-to-extend.
    private func hexByteView(byte: UInt8, absoluteIndex: Int) -> some View {
        Text(String(format: "%02x ", byte))
            .foregroundStyle(byteColor(byte))
            .background(isSelected(absoluteIndex) ? selectionHighlight : Color.clear)
            .onTapGesture {
                handleByteTap(absoluteIndex, extend: false)
            }
            #if os(macOS)
            .simultaneousGesture(
                TapGesture().modifiers(.shift).onEnded {
                    handleByteTap(absoluteIndex, extend: true)
                }
            )
            #endif
    }

    /// A single ASCII byte cell that mirrors selection highlighting.
    private func asciiByteView(byte: UInt8, absoluteIndex: Int) -> some View {
        Text(asciiCharacter(byte))
            .foregroundStyle(byteColor(byte))
            .background(isSelected(absoluteIndex) ? selectionHighlight : Color.clear)
            .onTapGesture {
                handleByteTap(absoluteIndex, extend: false)
            }
            #if os(macOS)
            .simultaneousGesture(
                TapGesture().modifiers(.shift).onEnded {
                    handleByteTap(absoluteIndex, extend: true)
                }
            )
            #endif
    }

    // MARK: - Selection logic

    private func isSelected(_ index: Int) -> Bool {
        guard let range = selectionRange else { return false }
        return range.contains(index)
    }

    private func handleByteTap(_ index: Int, extend: Bool) {
        if extend, selectionStart != nil {
            // Extend selection from the anchor (selectionStart) to the clicked byte
            selectionEnd = index
        } else {
            // New selection — single byte
            selectionStart = index
            selectionEnd = index
        }
    }

    private var selectionHighlight: Color {
        Color.accentColor.opacity(0.3)
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
