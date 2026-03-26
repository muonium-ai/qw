//
//  ExecutionConfirmDialog.swift
//  qw
//
//  Pre-execution confirmation dialog for sandboxed file execution.
//  Ticket: T-000060
//

import SwiftUI

#if os(macOS)

/// A sheet dialog that warns the user before executing a file in the sandbox.
struct ExecutionConfirmDialog: View {
    let fileName: String
    let formatName: String
    let sandboxSummary: [String]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
                .padding(.top, 28)
                .padding(.bottom, 12)

            // Title
            Text("Execute \(fileName)?")
                .font(.system(.title2, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            // Subtitle
            Text("Detected format: \(formatName)")
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)

            // Warning text
            Text("Executing files carries inherent risk. This file will run in a restricted sandbox with the following constraints:")
                .font(.system(.body))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // Sandbox restrictions list
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(sandboxSummary.enumerated()), id: \.offset) { _, restriction in
                    restrictionRow(restriction)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            Divider()

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Spacer()

                Button(action: { onConfirm() }) {
                    Label("Run in Sandbox", systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("executionConfirmDialog")
    }

    // MARK: - Restriction row

    private func restrictionRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName(for: text))
                .font(.system(.caption))
                .foregroundStyle(.orange)
                .frame(width: 16, alignment: .center)
            Text(text)
                .font(.system(.callout))
                .foregroundStyle(.primary)
        }
    }

    /// Choose an appropriate SF Symbol based on the restriction text.
    private func iconName(for restriction: String) -> String {
        let lower = restriction.lowercased()
        if lower.contains("network") {
            return "wifi.slash"
        } else if lower.contains("filesystem") || lower.contains("read-only") {
            return "lock.shield.fill"
        } else if lower.contains("memory") {
            return "memorychip"
        } else if lower.contains("cpu") || lower.contains("timeout") || lower.contains("time") {
            return "clock.fill"
        } else {
            return "shield.fill"
        }
    }
}

// MARK: - Preview

#Preview("Execution Confirm Dialog") {
    ExecutionConfirmDialog(
        fileName: "hello_world",
        formatName: "Mach-O 64-bit",
        sandboxSummary: [
            "No network access",
            "Filesystem: read-only",
            "Memory limit: 256 MB",
            "CPU timeout: 30s"
        ],
        onConfirm: {},
        onCancel: {}
    )
}

#endif
