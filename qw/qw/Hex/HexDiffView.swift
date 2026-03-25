//
//  HexDiffView.swift
//  qw
//
//  Side-by-side hex comparison of two binary files.
//  Displays diff regions with color-coded highlighting and synchronized scrolling.
//  Ticket: T-000029
//

import SwiftUI

/// Side-by-side hex diff view comparing two binary files.
///
/// Layout: left pane (file A) | center offset gutter | right pane (file B)
/// - 16 bytes per row in each pane
/// - Changed bytes: red/orange background
/// - Added bytes (in B only): green background
/// - Removed bytes (in A only): red background
/// - Equal bytes: default color
///
/// Uses a single ScrollView with LazyVStack for virtual scrolling.
struct HexDiffView: View {

    let dataA: Data
    let dataB: Data
    let nameA: String
    let nameB: String

    @State private var currentDiffIndex: Int = 0
    @State private var scrollTarget: Int?

    /// Precomputed diff regions.
    private var regions: [DiffRegion] {
        BinaryDiffEngine.diff(dataA: dataA, dataB: dataB)
    }

    /// Build a lookup table: for each byte offset, what is its diff type?
    /// Returns separate arrays for A and B sides.
    private var diffMaps: (a: [DiffRegionType], b: [DiffRegionType]) {
        let maxLen = max(dataA.count, dataB.count)
        var mapA = [DiffRegionType](repeating: .equal, count: dataA.count)
        var mapB = [DiffRegionType](repeating: .equal, count: dataB.count)

        for region in regions {
            switch region.type {
            case .equal, .changed:
                for i in 0..<region.length {
                    let offset = region.offsetA + i
                    if offset < mapA.count { mapA[offset] = region.type }
                    if offset < mapB.count { mapB[offset] = region.type }
                }
            case .removedFromA:
                for i in 0..<region.length {
                    let offset = region.offsetA + i
                    if offset < mapA.count { mapA[offset] = .removedFromA }
                }
            case .addedInB:
                for i in 0..<region.length {
                    let offset = region.offsetB + i
                    if offset < mapB.count { mapB[offset] = .addedInB }
                }
            }
        }
        return (mapA, mapB)
    }

    /// Total rows needed — based on the longer file.
    private var rowCount: Int {
        let maxBytes = max(dataA.count, dataB.count)
        return max((maxBytes + 15) / 16, 0)
    }

    /// Indices of diff regions that are non-equal.
    private var diffIndices: [Int] {
        BinaryDiffEngine.diffRegionIndices(in: regions)
    }

    /// Total number of differing bytes.
    private var differingCount: Int {
        BinaryDiffEngine.differingByteCount(in: regions)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            navigationBar

            // Main diff content
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<rowCount, id: \.self) { rowIndex in
                            diffRowView(rowIndex: rowIndex)
                                .id(rowIndex)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(rowIndex.isMultiple(of: 2) ? Color.clear : alternateRowBackground)
                        }
                    }
                }
                .onChange(of: scrollTarget) { _, target in
                    if let target = target {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                        scrollTarget = nil
                    }
                }
            }

            // Status bar
            statusBar
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Button(action: previousDiff) {
                Image(systemName: "chevron.up")
            }
            .help("Previous Diff")
            .disabled(diffIndices.isEmpty)

            Button(action: nextDiff) {
                Image(systemName: "chevron.down")
            }
            .help("Next Diff")
            .disabled(diffIndices.isEmpty)

            if !diffIndices.isEmpty {
                Text("\(currentDiffIndex + 1) of \(diffIndices.count) differences")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("Files are identical")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Legend
            HStack(spacing: 12) {
                legendItem(color: .orange.opacity(0.4), label: "Changed")
                legendItem(color: .green.opacity(0.4), label: "Added")
                legendItem(color: .red.opacity(0.4), label: "Removed")
            }
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

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Diff Row

    private func diffRowView(rowIndex: Int) -> some View {
        let maps = diffMaps
        let offset = rowIndex * 16

        return HStack(spacing: 0) {
            // Left pane (file A)
            hexPaneBytes(data: dataA, offset: offset, diffMap: maps.a, side: .left)

            // Center offset gutter
            Text(String(format: " %08x ", offset))
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))

            // Right pane (file B)
            hexPaneBytes(data: dataB, offset: offset, diffMap: maps.b, side: .right)
        }
        .font(.system(.body, design: .monospaced))
    }

    private enum PaneSide {
        case left, right
    }

    private func hexPaneBytes(data: Data, offset: Int, diffMap: [DiffRegionType], side: PaneSide) -> some View {
        HStack(spacing: 0) {
            // Hex bytes
            ForEach(0..<16, id: \.self) { i in
                let byteIndex = offset + i
                if byteIndex < data.count {
                    let byte = data[data.startIndex + byteIndex]
                    let diffType = byteIndex < diffMap.count ? diffMap[byteIndex] : .equal
                    Text(String(format: "%02x ", byte))
                        .foregroundStyle(byteColor(byte))
                        .background(backgroundForDiffType(diffType))
                } else {
                    Text("   ")
                }

                // Wider gap after byte 8
                if i == 7 {
                    Text(" ")
                }
            }

            Text(" ")

            // ASCII sidebar
            Text("|")
                .foregroundStyle(.secondary)
            ForEach(0..<16, id: \.self) { i in
                let byteIndex = offset + i
                if byteIndex < data.count {
                    let byte = data[data.startIndex + byteIndex]
                    let diffType = byteIndex < diffMap.count ? diffMap[byteIndex] : .equal
                    Text(asciiCharacter(byte))
                        .foregroundStyle(byteColor(byte))
                        .background(backgroundForDiffType(diffType))
                } else {
                    Text(" ")
                }
            }
            Text("|")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text(nameA)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("(\(fileSizeString(dataA.count)))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("  vs  ")
                .foregroundStyle(.secondary)

            Text(nameB)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("(\(fileSizeString(dataB.count)))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(differingCount) differing bytes")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(differingCount > 0 ? .orange : .secondary)
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

    // MARK: - Navigation

    private func nextDiff() {
        guard !diffIndices.isEmpty else { return }
        currentDiffIndex = (currentDiffIndex + 1) % diffIndices.count
        scrollToDiff()
    }

    private func previousDiff() {
        guard !diffIndices.isEmpty else { return }
        currentDiffIndex = (currentDiffIndex - 1 + diffIndices.count) % diffIndices.count
        scrollToDiff()
    }

    private func scrollToDiff() {
        guard !diffIndices.isEmpty else { return }
        let regionIndex = diffIndices[currentDiffIndex]
        let region = regions[regionIndex]
        let byteOffset = max(region.offsetA, region.offsetB)
        let rowIndex = byteOffset / 16
        scrollTarget = rowIndex
    }

    // MARK: - Helpers

    private func backgroundForDiffType(_ type: DiffRegionType) -> Color {
        switch type {
        case .equal:
            return .clear
        case .changed:
            return .orange.opacity(0.4)
        case .addedInB:
            return .green.opacity(0.4)
        case .removedFromA:
            return .red.opacity(0.4)
        }
    }

    private func asciiCharacter(_ byte: UInt8) -> String {
        if byte >= 0x20 && byte <= 0x7E {
            return String(UnicodeScalar(byte))
        }
        return "."
    }

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

    private func fileSizeString(_ count: Int) -> String {
        if count < 1024 {
            return "\(count) bytes"
        } else if count < 1024 * 1024 {
            return String(format: "%.1f KB", Double(count) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(count) / (1024.0 * 1024.0))
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

// MARK: - Previews

#Preview("Hex Diff View") {
    let a = "Hello, World! This is file A with some content.\n".data(using: .utf8)!
    let b = "Hello, World! This is file B with different content and more.\n".data(using: .utf8)!
    HexDiffView(dataA: a, dataB: b, nameA: "fileA.bin", nameB: "fileB.bin")
}

#Preview("Hex Diff View — identical") {
    let data = "Identical content.".data(using: .utf8)!
    HexDiffView(dataA: data, dataB: data, nameA: "same.bin", nameB: "same.bin")
}
