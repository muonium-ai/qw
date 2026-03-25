//
//  GoToOffsetView.swift
//  qw
//
//  Small popover dialog for jumping to a byte offset in hex mode.
//  Accepts decimal or hex (0x prefix) offsets.
//  Ticket: T-000022
//

import SwiftUI

/// Go-to-offset popover for hex mode (Cmd+G).
struct GoToOffsetView: View {
    @Binding var isPresented: Bool
    let dataCount: Int
    let onGo: (Int) -> Void

    @State private var offsetText: String = ""
    @State private var errorMessage: String?

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        EditorSettingsManager.shared.syntaxTheme(for: colorScheme).background
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.to.line")
                    .foregroundColor(.secondary)

                TextField("Offset (decimal or 0x hex)", text: $offsetText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("goToOffsetField")
                    #if os(macOS)
                    .onSubmit { go() }
                    #endif

                Button("Go") { go() }
                    .buttonStyle(.borderless)
                    .disabled(offsetText.isEmpty)

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text("Range: 0 \u{2013} \(String(format: "0x%X", max(dataCount - 1, 0))) (\(dataCount) bytes)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .cornerRadius(8)
        .padding(8)
    }

    private func go() {
        errorMessage = nil
        let trimmed = offsetText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let parsed: Int?
        if trimmed.lowercased().hasPrefix("0x") {
            let hexPart = String(trimmed.dropFirst(2))
            parsed = Int(hexPart, radix: 16)
        } else {
            parsed = Int(trimmed)
        }

        guard let offset = parsed else {
            errorMessage = "Invalid number format."
            return
        }

        guard offset >= 0, offset < dataCount else {
            errorMessage = "Offset out of range (0 \u{2013} \(String(format: "0x%X", max(dataCount - 1, 0))))."
            return
        }

        onGo(offset)
        isPresented = false
    }
}
