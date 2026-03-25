//
//  AnnotationPanelView.swift
//  qw
//
//  Collapsible panel displaying decoded file format annotations for the hex view.
//  Ticket: T-000027
//

import SwiftUI

/// Displays decoded field annotations as a list: field name, offset range,
/// raw hex bytes, and the human-readable decoded value.
struct AnnotationPanelView: View {

    let annotations: [FieldValue]

    @Environment(\.colorScheme) private var colorScheme

    private var theme: SyntaxTheme {
        EditorSettingsManager.shared.syntaxTheme(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if annotations.isEmpty {
                emptyState
            } else {
                annotationList
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
        ScrollView {
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
    AnnotationPanelView(annotations: sampleAnnotations)
}
