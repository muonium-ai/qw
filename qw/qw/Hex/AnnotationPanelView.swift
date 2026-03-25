//
//  AnnotationPanelView.swift
//  qw
//
//  Collapsible panel displaying decoded file format annotations for the hex view.
//  Ticket: T-000027, T-000041
//

import SwiftUI

/// Displays decoded field annotations as a list: field name, offset range,
/// raw hex bytes, and the human-readable decoded value.
/// When EXIF metadata is available (for JPEG/PNG), it is shown in a separate
/// collapsible section below the format annotations.
struct AnnotationPanelView: View {

    let annotations: [FieldValue]
    var exifMetadata: ExifMetadata = ExifMetadata(entries: [])

    @Environment(\.colorScheme) private var colorScheme

    private var theme: SyntaxTheme {
        EditorSettingsManager.shared.syntaxTheme(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if annotations.isEmpty && exifMetadata.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if !annotations.isEmpty {
                            annotationList
                        }
                        if !exifMetadata.isEmpty {
                            if !annotations.isEmpty {
                                Divider().padding(.vertical, 4)
                            }
                            exifSection
                        }
                    }
                }
            }
        }
        .frame(width: 320)
        .background(theme.background)
    }

    // MARK: - Header

    private var header: some View {
        Text("Format Annotations")
            .font(.system(.headline))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("No known format detected")
                    .foregroundStyle(.secondary)
                    .font(.system(.caption))
                Spacer()
            }
            Spacer()
        }
    }

    // MARK: - Annotation list

    private var annotationList: some View {
        VStack(spacing: 0) {
            ForEach(Array(annotations.enumerated()), id: \.offset) { index, fieldValue in
                annotationRow(fieldValue)
                if index < annotations.count - 1 {
                    Divider().padding(.horizontal, 8)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - EXIF metadata section

    /// Groups EXIF entries by category and displays them as key-value rows.
    private var exifSection: some View {
        let grouped = groupedExifEntries()
        return VStack(alignment: .leading, spacing: 0) {
            Text("EXIF Metadata")
                .font(.system(.headline))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            Divider()
            ForEach(grouped, id: \.category) { group in
                VStack(alignment: .leading, spacing: 0) {
                    // Category header
                    Text(group.category)
                        .font(.system(.caption, design: .default).bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                    ForEach(Array(group.entries.enumerated()), id: \.offset) { index, entry in
                        exifRow(entry)
                        if index < group.entries.count - 1 {
                            Divider().padding(.horizontal, 8)
                        }
                    }
                }
                Divider().padding(.horizontal, 4)
            }
        }
    }

    private func exifRow(_ entry: ExifMetadata.Entry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.key)
                .font(.system(.caption, design: .default))
                .foregroundStyle(.secondary)
                .frame(minWidth: 100, alignment: .leading)
            Spacer()
            Text(entry.value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    /// Group EXIF entries by category, preserving insertion order.
    private func groupedExifEntries() -> [ExifGroup] {
        var groups: [String: [ExifMetadata.Entry]] = [:]
        var order: [String] = []
        for entry in exifMetadata.entries {
            if groups[entry.category] == nil {
                order.append(entry.category)
                groups[entry.category] = []
            }
            groups[entry.category]?.append(entry)
        }
        return order.map { ExifGroup(category: $0, entries: groups[$0] ?? []) }
    }

    // MARK: - Row

    private func annotationRow(_ fieldValue: FieldValue) -> some View {
        let desc = fieldValue.descriptor
        let offsetEnd = desc.offset + desc.size - 1
        let offsetLabel = desc.size == 1
            ? String(format: "@0x%X", desc.offset)
            : String(format: "@0x%X\u{2013}0x%X", desc.offset, offsetEnd)
        let sizeLabel = desc.size == 1 ? "1 byte" : "\(desc.size) bytes"
        let rawHex = fieldValue.rawBytes.map { String(format: "%02X", $0) }.joined(separator: " ")

        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(desc.name)
                    .font(.system(.caption, design: .default).bold())
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(offsetLabel) (\(sizeLabel))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(rawHex)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\u{2192}")
                    .font(.system(.caption2))
                    .foregroundStyle(.secondary)
                Text(fieldValue.displayValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - EXIF grouping helper

/// A group of EXIF entries sharing the same category.
private struct ExifGroup {
    let category: String
    let entries: [ExifMetadata.Entry]
}

// MARK: - Preview

#Preview("Annotation Panel") {
    let sampleAnnotations: [FieldValue] = [
        FieldValue(
            descriptor: FieldDescriptor(name: "PNG Signature", offset: 0, size: 8, type: .magic, endianness: .big),
            rawBytes: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
            displayValue: "89 50 4E 47 0D 0A 1A 0A"
        ),
        FieldValue(
            descriptor: FieldDescriptor(name: "Width", offset: 16, size: 4, type: .uint32, endianness: .big),
            rawBytes: Data([0x00, 0x00, 0x03, 0x20]),
            displayValue: "800"
        ),
        FieldValue(
            descriptor: FieldDescriptor(name: "Height", offset: 20, size: 4, type: .uint32, endianness: .big),
            rawBytes: Data([0x00, 0x00, 0x02, 0x58]),
            displayValue: "600"
        ),
    ]
    let sampleExif = ExifMetadata(entries: [
        .init(category: "Image", key: "Pixel Width", value: "4032"),
        .init(category: "Image", key: "Pixel Height", value: "3024"),
        .init(category: "TIFF", key: "Camera Make", value: "Apple"),
        .init(category: "TIFF", key: "Camera Model", value: "iPhone 15 Pro"),
        .init(category: "EXIF", key: "Date Taken", value: "2024:06:15 14:32:01"),
        .init(category: "EXIF", key: "Exposure Time", value: "1/120 s"),
        .init(category: "EXIF", key: "F-Number", value: "f/1.8"),
        .init(category: "EXIF", key: "ISO Speed", value: "ISO 64"),
        .init(category: "EXIF", key: "Focal Length", value: "6.9 mm"),
        .init(category: "GPS", key: "Latitude", value: "37\u{00B0} 47' 15.2\" N"),
        .init(category: "GPS", key: "Longitude", value: "122\u{00B0} 25' 10.8\" W"),
    ])
    AnnotationPanelView(annotations: sampleAnnotations, exifMetadata: sampleExif)
}
