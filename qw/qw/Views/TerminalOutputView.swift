//
//  TerminalOutputView.swift
//  qw
//
//  Terminal-like output panel for displaying captured stdout/stderr from
//  sandboxed execution.
//  Ticket: T-000060
//

import SwiftUI

#if os(macOS)
import AppKit

/// Displays execution output in a terminal-like panel with dark background
/// and monospace font.
struct TerminalOutputView: View {
    let stdout: String
    let stderr: String
    let isRunning: Bool
    let exitCode: Int32?
    let elapsedTime: Double
    let timedOut: Bool
    var onKill: (() -> Void)?

    /// Maximum number of characters to display before truncating.
    private static let maxDisplayLength = 500_000

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            outputArea
        }
        .background(terminalBackground)
        .accessibilityIdentifier("terminalOutputView")
    }

    // MARK: - Terminal background

    private var terminalBackground: Color {
        Color(nsColor: NSColor(white: 0.1, alpha: 1))
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            // Status indicator dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Status label
            Text(statusLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)

            // Elapsed time
            Text(formattedElapsedTime)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.gray)

            Spacer()

            // Exit code badge
            if let code = exitCode {
                exitCodeBadge(code)
            }

            // Kill button
            if isRunning, let onKill {
                Button(action: onKill) {
                    Label("Kill", systemImage: "xmark.circle.fill")
                        .font(.system(.caption))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .accessibilityIdentifier("killProcessButton")
            }

            // Copy button
            Button(action: copyAllOutput) {
                Image(systemName: "doc.on.doc")
                    .font(.system(.caption))
            }
            .buttonStyle(.bordered)
            .tint(.gray)
            .controlSize(.small)
            .help("Copy all output")
            .accessibilityIdentifier("copyOutputButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: NSColor(white: 0.15, alpha: 1)))
    }

    private var statusColor: Color {
        if isRunning {
            return .green
        } else if timedOut {
            return .orange
        } else if let code = exitCode, code != 0 {
            return .red
        } else {
            return .gray
        }
    }

    private var statusLabel: String {
        if isRunning {
            return "Running..."
        } else if timedOut {
            return "Timed Out"
        } else if let code = exitCode, code == -1 {
            return "Killed"
        } else {
            return "Completed"
        }
    }

    private var formattedElapsedTime: String {
        if elapsedTime < 1 {
            return String(format: "%.0f ms", elapsedTime * 1000)
        } else if elapsedTime < 60 {
            return String(format: "%.1f s", elapsedTime)
        } else {
            let minutes = Int(elapsedTime) / 60
            let seconds = Int(elapsedTime) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func exitCodeBadge(_ code: Int32) -> some View {
        Text("exit \(code)")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(code == 0 ? .green : .red)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill((code == 0 ? Color.green : Color.red).opacity(0.15))
            )
    }

    // MARK: - Output area

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    outputLines
                    // Anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("terminal-bottom")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: stdout) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: stderr) { _, _ in
                scrollToBottom(proxy)
            }
            .onAppear {
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.1)) {
            proxy.scrollTo("terminal-bottom", anchor: .bottom)
        }
    }

    @ViewBuilder
    private var outputLines: some View {
        let combined = buildOutputLines()
        let isTruncated = combined.isTruncated

        ForEach(Array(combined.lines.enumerated()), id: \.offset) { _, line in
            Text(line.text)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(line.isStderr ? .orange : Color(nsColor: NSColor(white: 0.85, alpha: 1)))
                .textSelection(.enabled)
        }

        if isTruncated {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle")
                Text("Output truncated — copy to clipboard for full output")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.yellow)
            .padding(.top, 8)
        }

        if isRunning {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Waiting for output...")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.gray)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Output parsing

    private struct OutputLine {
        let text: String
        let isStderr: Bool
    }

    private struct CombinedOutput {
        let lines: [OutputLine]
        let isTruncated: Bool
    }

    private func buildOutputLines() -> CombinedOutput {
        let totalLength = stdout.count + stderr.count
        let isTruncated = totalLength > Self.maxDisplayLength

        var lines: [OutputLine] = []

        // stdout lines
        let stdoutText = isTruncated
            ? String(stdout.prefix(Self.maxDisplayLength / 2))
            : stdout
        if !stdoutText.isEmpty {
            for line in stdoutText.components(separatedBy: "\n") {
                lines.append(OutputLine(text: line, isStderr: false))
            }
        }

        // stderr lines
        let stderrText = isTruncated
            ? String(stderr.prefix(Self.maxDisplayLength / 2))
            : stderr
        if !stderrText.isEmpty {
            for line in stderrText.components(separatedBy: "\n") {
                lines.append(OutputLine(text: line, isStderr: true))
            }
        }

        if lines.isEmpty {
            lines.append(OutputLine(text: "", isStderr: false))
        }

        return CombinedOutput(lines: lines, isTruncated: isTruncated)
    }

    // MARK: - Copy

    private func copyAllOutput() {
        var combined = ""
        if !stdout.isEmpty {
            combined += stdout
        }
        if !stderr.isEmpty {
            if !combined.isEmpty { combined += "\n" }
            combined += stderr
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
    }
}

// MARK: - Preview

#Preview("Terminal — Running") {
    TerminalOutputView(
        stdout: "Hello, world!\nProcessing data...\nLine 3 of output",
        stderr: "",
        isRunning: true,
        exitCode: nil,
        elapsedTime: 1.5,
        timedOut: false,
        onKill: {}
    )
    .frame(width: 600, height: 300)
}

#Preview("Terminal — Completed with Error") {
    TerminalOutputView(
        stdout: "Starting process...\nLoading config...",
        stderr: "Error: segmentation fault\ncore dumped",
        isRunning: false,
        exitCode: 139,
        elapsedTime: 0.234,
        timedOut: false
    )
    .frame(width: 600, height: 300)
}

#Preview("Terminal — Timed Out") {
    TerminalOutputView(
        stdout: "Running infinite loop...",
        stderr: "",
        isRunning: false,
        exitCode: nil,
        elapsedTime: 30.0,
        timedOut: true
    )
    .frame(width: 600, height: 300)
}

#endif
