//
//  DataInspectorView.swift
//  qw
//
//  Data Inspector panel: decodes bytes at cursor position as multiple types.
//  Ticket: T-000028
//

import SwiftUI

/// Displays file information and the bytes at a given cursor offset decoded
/// as multiple numeric, text, and floating-point types.
/// Shown as a right-side panel in the hex view.
struct DataInspectorView: View {

    let data: Data
    let cursorOffset: Int?
    @Binding var isLittleEndian: Bool

    // File info parameters
    let fileURL: URL?
    let fileSize: Int
    let detectedFormat: String?
    let detectedCategory: String?

    @Environment(\.colorScheme) private var colorScheme

    private var theme: SyntaxTheme {
        EditorSettingsManager.shared.syntaxTheme(for: colorScheme)
    }

    /// File attributes fetched once from the filesystem.
    private var fileAttributes: [FileAttributeKey: Any]? {
        guard let path = fileURL?.path else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: path)
    }

    /// Up to 8 bytes starting at `cursorOffset`.
    private var slice: Data {
        guard let offset = cursorOffset, offset >= 0, offset < data.count else {
            return Data()
        }
        let start = data.startIndex + offset
        let end = min(start + 8, data.endIndex)
        return Data(data[start..<end])
    }

    private var available: Int { slice.count }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    // MARK: File Info section (always visible)
                    fileInfoSection

                    Divider().padding(.vertical, 4)

                    // MARK: Byte Inspector section (conditional on selection)
                    if cursorOffset != nil && available > 0 {
                        Text("Byte Inspector")
                            .font(.system(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 2)

                        inspectorRow("Offset", offsetValue)
                        inspectorRow("Hex", hexValue)
                        inspectorRow("Binary", binaryValue)
                        Divider().padding(.vertical, 2)
                        inspectorRow("Int8", int8Value)
                        inspectorRow("UInt8", uint8Value)
                        inspectorRow("Int16", int16Value)
                        inspectorRow("UInt16", uint16Value)
                        inspectorRow("Int32", int32Value)
                        inspectorRow("UInt32", uint32Value)
                        inspectorRow("Int64", int64Value)
                        inspectorRow("UInt64", uint64Value)
                        Divider().padding(.vertical, 2)
                        inspectorRow("Float32", float32Value)
                        inspectorRow("Float64", float64Value)
                        Divider().padding(.vertical, 2)
                        inspectorRow("ASCII", asciiValue)
                        inspectorRow("UTF-8", utf8Value)
                    } else {
                        Text("Select a byte to inspect")
                            .foregroundStyle(.secondary)
                            .font(.system(.caption))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .frame(width: 220)
        .background(theme.background)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("Data Inspector")
                .font(.system(.headline))
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: $isLittleEndian) {
                Text("Little Endian").tag(true)
                Text("Big Endian").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - File Info section

    private var fileInfoSection: some View {
        VStack(spacing: 2) {
            Text("File Info")
                .font(.system(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)

            if let url = fileURL {
                inspectorRow("Filename", url.lastPathComponent)
                inspectorRow("Path", url.deletingLastPathComponent().path)
                inspectorRow("Extension", url.pathExtension.isEmpty ? "\u{2014}" : url.pathExtension)
            }

            inspectorRow("Size", Self.humanReadableSize(fileSize))

            if let format = detectedFormat {
                inspectorRow("Format", format)
            }
            if let category = detectedCategory {
                inspectorRow("Category", category)
            }

            if let attrs = fileAttributes {
                if let created = attrs[.creationDate] as? Date {
                    inspectorRow("Created", Self.formatDate(created))
                }
                if let modified = attrs[.modificationDate] as? Date {
                    inspectorRow("Modified", Self.formatDate(modified))
                }
                if let posix = attrs[.posixPermissions] as? Int {
                    inspectorRow("Permissions", Self.posixString(posix))
                }
            }
        }
    }

    // MARK: - Format helpers

    /// Convert byte count to human-readable string, e.g. "1,048,576 bytes (1.0 MB)".
    static func humanReadableSize(_ bytes: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formattedBytes = formatter.string(from: NSNumber(value: bytes)) ?? "\(bytes)"

        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(formattedBytes) bytes"
        }
        return "\(formattedBytes) bytes (\(String(format: "%.1f", value)) \(units[unitIndex]))"
    }

    /// Format a date using medium style.
    static func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    /// Convert POSIX permissions number to rwx string with octal, e.g. "rwxr-xr-x (755)".
    static func posixString(_ mode: Int) -> String {
        func triplet(_ val: Int) -> String {
            let r = (val & 4) != 0 ? "r" : "-"
            let w = (val & 2) != 0 ? "w" : "-"
            let x = (val & 1) != 0 ? "x" : "-"
            return r + w + x
        }
        let owner = triplet((mode >> 6) & 7)
        let group = triplet((mode >> 3) & 7)
        let other = triplet(mode & 7)
        let octal = String(format: "%o", mode)
        return "\(owner)\(group)\(other) (\(octal))"
    }

    // MARK: - Row view

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(.caption))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    // MARK: - Decoders

    private var offsetValue: String {
        guard let offset = cursorOffset else { return "\u{2014}" }
        return String(format: "0x%08X", offset)
    }

    private var hexValue: String {
        slice.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private var binaryValue: String {
        guard available >= 1 else { return "\u{2014}" }
        let byte = slice[slice.startIndex]
        return String(byte, radix: 2).leftPadded(toLength: 8, with: "0")
    }

    // Integer decoders

    private var int8Value: String {
        guard available >= 1 else { return "\u{2014}" }
        let raw = slice[slice.startIndex]
        return "\(Int8(bitPattern: raw))"
    }

    private var uint8Value: String {
        guard available >= 1 else { return "\u{2014}" }
        return "\(slice[slice.startIndex])"
    }

    private var int16Value: String {
        guard available >= 2 else { return "\u{2014}" }
        let raw = readUInt16()
        return "\(Int16(bitPattern: raw))"
    }

    private var uint16Value: String {
        guard available >= 2 else { return "\u{2014}" }
        return "\(readUInt16())"
    }

    private var int32Value: String {
        guard available >= 4 else { return "\u{2014}" }
        let raw = readUInt32()
        return "\(Int32(bitPattern: raw))"
    }

    private var uint32Value: String {
        guard available >= 4 else { return "\u{2014}" }
        return "\(readUInt32())"
    }

    private var int64Value: String {
        guard available >= 8 else { return "\u{2014}" }
        let raw = readUInt64()
        return "\(Int64(bitPattern: raw))"
    }

    private var uint64Value: String {
        guard available >= 8 else { return "\u{2014}" }
        return "\(readUInt64())"
    }

    // Floating-point decoders

    private var float32Value: String {
        guard available >= 4 else { return "\u{2014}" }
        let bits = readUInt32()
        let value = Float(bitPattern: bits)
        if value.isNaN { return "NaN" }
        if value == .infinity { return "Inf" }
        if value == -.infinity { return "-Inf" }
        return "\(value)"
    }

    private var float64Value: String {
        guard available >= 8 else { return "\u{2014}" }
        let bits = readUInt64()
        let value = Double(bitPattern: bits)
        if value.isNaN { return "NaN" }
        if value == .infinity { return "Inf" }
        if value == -.infinity { return "-Inf" }
        return "\(value)"
    }

    // Text decoders

    private var asciiValue: String {
        guard available >= 1 else { return "\u{2014}" }
        let byte = slice[slice.startIndex]
        if byte >= 0x20 && byte <= 0x7E {
            return String(UnicodeScalar(byte))
        }
        return "\u{00B7}" // middle dot
    }

    private var utf8Value: String {
        guard available >= 1 else { return "\u{2014}" }
        // Try to decode a valid UTF-8 character starting at the first byte
        let firstByte = slice[slice.startIndex]
        let charLen: Int
        if firstByte & 0x80 == 0 {
            charLen = 1
        } else if firstByte & 0xE0 == 0xC0 {
            charLen = 2
        } else if firstByte & 0xF0 == 0xE0 {
            charLen = 3
        } else if firstByte & 0xF8 == 0xF0 {
            charLen = 4
        } else {
            return "\u{2014}" // not a valid start byte
        }
        guard available >= charLen else { return "\u{2014}" }
        let charBytes = slice[slice.startIndex..<slice.startIndex + charLen]
        if let str = String(data: Data(charBytes), encoding: .utf8) {
            return str
        }
        return "\u{2014}"
    }

    // MARK: - Raw byte readers

    private func readUInt16() -> UInt16 {
        var value: UInt16 = 0
        let bytes = slice.prefix(2)
        withUnsafeMutableBytes(of: &value) { buf in
            bytes.copyBytes(to: buf.bindMemory(to: UInt8.self))
        }
        return isLittleEndian ? value.littleEndian : value.bigEndian
    }

    private func readUInt32() -> UInt32 {
        var value: UInt32 = 0
        let bytes = slice.prefix(4)
        withUnsafeMutableBytes(of: &value) { buf in
            bytes.copyBytes(to: buf.bindMemory(to: UInt8.self))
        }
        return isLittleEndian ? value.littleEndian : value.bigEndian
    }

    private func readUInt64() -> UInt64 {
        var value: UInt64 = 0
        let bytes = slice.prefix(8)
        withUnsafeMutableBytes(of: &value) { buf in
            bytes.copyBytes(to: buf.bindMemory(to: UInt8.self))
        }
        return isLittleEndian ? value.littleEndian : value.bigEndian
    }
}

// MARK: - String helper

private extension String {
    func leftPadded(toLength length: Int, with pad: Character) -> String {
        let deficit = length - count
        if deficit <= 0 { return self }
        return String(repeating: pad, count: deficit) + self
    }
}

// MARK: - Preview

#Preview("Data Inspector") {
    struct Wrapper: View {
        @State private var isLittleEndian = true
        var body: some View {
            DataInspectorView(
                data: "Hello, World!".data(using: .utf8)!,
                cursorOffset: 0,
                isLittleEndian: $isLittleEndian,
                fileURL: nil,
                fileSize: 13,
                detectedFormat: "Plain Text",
                detectedCategory: "text"
            )
        }
    }
    return Wrapper()
}
