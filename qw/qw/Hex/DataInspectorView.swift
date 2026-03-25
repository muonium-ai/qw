//
//  DataInspectorView.swift
//  qw
//
//  Data Inspector panel: decodes bytes at cursor position as multiple types.
//  Ticket: T-000028
//

import SwiftUI

/// Displays the bytes at a given cursor offset decoded as multiple numeric,
/// text, and floating-point types. Shown as a right-side panel in the hex view.
struct DataInspectorView: View {

    let data: Data
    let cursorOffset: Int?
    @Binding var isLittleEndian: Bool

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
            if cursorOffset != nil && available > 0 {
                ScrollView {
                    VStack(spacing: 2) {
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
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text("Select a byte")
                        .foregroundStyle(.secondary)
                        .font(.system(.caption))
                    Spacer()
                }
                Spacer()
            }
        }
        .frame(width: 220)
        #if os(macOS)
        .background(Color(nsColor: .controlBackgroundColor))
        #else
        .background(Color(uiColor: .secondarySystemBackground))
        #endif
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
                isLittleEndian: $isLittleEndian
            )
        }
    }
    return Wrapper()
}
