//
//  ExecutableRunnerView.swift
//  qw
//
//  Container view that combines the confirmation dialog and terminal output
//  for sandboxed executable execution.
//  Ticket: T-000060
//

import SwiftUI

#if os(macOS)

/// Execution lifecycle states.
enum ExecutionState {
    case confirming
    case running
    case completed
}

/// A container view managing the full lifecycle of executing a file:
/// confirmation, live output, and results.
struct ExecutableRunnerView: View {
    let fileURL: URL
    let formatName: String
    let sandboxSummary: [String]
    var onSwitchToHex: (() -> Void)?

    @State private var state: ExecutionState = .confirming
    @State private var stdout: String = ""
    @State private var stderr: String = ""
    @State private var exitCode: Int32?
    @State private var elapsedTime: Double = 0
    @State private var timedOut: Bool = false
    @State private var startTime: Date?
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with file info and mode switch
            topBar
            Divider()

            // Main content based on state
            switch state {
            case .confirming:
                confirmationContent
            case .running, .completed:
                terminalContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("executableRunnerView")
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.secondary)
            Text(fileURL.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
            Text("(\(formatName))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()

            if let onSwitchToHex {
                Button(action: onSwitchToHex) {
                    Label("Hex View", systemImage: "number")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Confirmation content

    private var confirmationContent: some View {
        ExecutionConfirmDialog(
            fileName: fileURL.lastPathComponent,
            formatName: formatName,
            sandboxSummary: sandboxSummary,
            onConfirm: {
                beginExecution()
            },
            onCancel: {
                // Switch to hex view on cancel
                if let onSwitchToHex {
                    onSwitchToHex()
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Terminal content

    private var terminalContent: some View {
        TerminalOutputView(
            stdout: stdout,
            stderr: stderr,
            isRunning: state == .running,
            exitCode: exitCode,
            elapsedTime: elapsedTime,
            timedOut: timedOut,
            onKill: state == .running ? { killProcess() } : nil
        )
    }

    // MARK: - Execution lifecycle

    /// Begin execution — transitions from confirming to running state.
    /// The actual process spawning will be wired up in a future ticket;
    /// this sets up the UI state and elapsed-time timer.
    private func beginExecution() {
        state = .running
        stdout = ""
        stderr = ""
        exitCode = nil
        timedOut = false
        elapsedTime = 0

        let start = Date()
        startTime = start

        // Elapsed time update timer
        let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            elapsedTime = Date().timeIntervalSince(start)
        }
        timer = t
    }

    /// Mark execution as completed with the given results.
    func markCompleted(exitCode: Int32, timedOut: Bool = false) {
        timer?.invalidate()
        timer = nil
        self.exitCode = exitCode
        self.timedOut = timedOut
        if let start = startTime {
            elapsedTime = Date().timeIntervalSince(start)
        }
        state = .completed
    }

    /// Kill the running process.
    private func killProcess() {
        // Actual process termination will be wired up in a future ticket.
        // For now, transition to completed with a killed indicator.
        markCompleted(exitCode: -1)
    }

    /// Append text to the stdout buffer (called from the process runner).
    func appendStdout(_ text: String) {
        stdout += text
    }

    /// Append text to the stderr buffer (called from the process runner).
    func appendStderr(_ text: String) {
        stderr += text
    }
}

// MARK: - Preview

#Preview("Executable Runner — Confirming") {
    ExecutableRunnerView(
        fileURL: URL(fileURLWithPath: "/usr/bin/hello_world"),
        formatName: "Mach-O 64-bit",
        sandboxSummary: [
            "No network access",
            "Filesystem: read-only",
            "Memory limit: 256 MB",
            "CPU timeout: 30s"
        ],
        onSwitchToHex: {}
    )
    .frame(width: 600, height: 500)
}

#endif
