//
//  WineRunner.swift
//  qw
//
//  Runner for Windows PE executables using Wine, wrapped in the sandbox
//  framework.  Creates a disposable WINEPREFIX for each execution and
//  cleans it up afterwards.
//  Ticket: T-000058
//

import Foundation
import os

/// Runs Windows PE (.exe) files inside Wine with a sandboxed, disposable
/// WINEPREFIX.  Wine's debug output is suppressed via `WINEDEBUG=-all`.
enum WineRunner {

    private static let logger = Logger(subsystem: "com.muonium.qw", category: "wine")

    // MARK: - Wine discovery

    /// Well-known paths where Wine may be installed on macOS.
    private static let wellKnownPaths: [String] = [
        "/usr/local/bin/wine",
        "/opt/homebrew/bin/wine",
        "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine",
    ]

    /// Check whether Wine is available on this system.
    ///
    /// - Returns: A tuple indicating availability, the resolved Wine binary
    ///   path (if found), and a human-readable install hint (if not found).
    static func isAvailable() -> (available: Bool, winePath: String?, installHint: String?) {
        let fm = FileManager.default

        // Check well-known locations first.
        for path in wellKnownPaths {
            if fm.isExecutableFile(atPath: path) {
                logger.info("[wine] Found Wine at \(path, privacy: .public)")
                return (available: true, winePath: path, installHint: nil)
            }
        }

        // Fall back to `which wine`.
        let whichResult = Self.which("wine")
        if let resolved = whichResult {
            logger.info("[wine] Found Wine via which: \(resolved, privacy: .public)")
            return (available: true, winePath: resolved, installHint: nil)
        }

        logger.info("[wine] Wine not found on this system")
        return (
            available: false,
            winePath: nil,
            installHint: "Install Wine via: brew install --cask wine-stable"
        )
    }

    // MARK: - Execution

    /// Run a Windows PE executable inside Wine with a sandboxed, disposable
    /// WINEPREFIX.
    ///
    /// - Parameter fileURL: URL of the `.exe` file to execute.
    /// - Returns: A `SandboxResult` with captured stdout/stderr and exit info.
    static func run(fileURL: URL) async -> SandboxResult {
        // 1. Verify Wine is available.
        let availability = isAvailable()
        guard let winePath = availability.winePath else {
            let hint = availability.installHint ?? "Wine is not installed."
            logger.error("[wine] Cannot run — Wine not found")
            FormatLogger.logOpenFailure(
                fileURL: fileURL,
                formatName: "Windows PE/EXE",
                mode: "wine",
                error: hint
            )
            return SandboxResult(
                exitCode: -1,
                stdout: "",
                stderr: hint,
                timedOut: false,
                killedByUser: false,
                elapsedSeconds: 0
            )
        }

        // 2. Create a disposable temp directory to hold the WINEPREFIX.
        let baseTempDir: URL
        do {
            baseTempDir = try SandboxEnvironment.createTempDir()
        } catch {
            let msg = "Failed to create temp directory for WINEPREFIX: \(error.localizedDescription)"
            logger.error("[wine] \(msg, privacy: .public)")
            return SandboxResult(
                exitCode: -1,
                stdout: "",
                stderr: msg,
                timedOut: false,
                killedByUser: false,
                elapsedSeconds: 0
            )
        }

        let winePrefixDir = baseTempDir.appendingPathComponent("wineprefix", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: winePrefixDir, withIntermediateDirectories: true)
        } catch {
            let msg = "Failed to create WINEPREFIX directory: \(error.localizedDescription)"
            logger.error("[wine] \(msg, privacy: .public)")
            SandboxEnvironment.cleanup(tempDir: baseTempDir)
            return SandboxResult(
                exitCode: -1,
                stdout: "",
                stderr: msg,
                timedOut: false,
                killedByUser: false,
                elapsedSeconds: 0
            )
        }

        // Ensure the entire disposable tree is cleaned up when we're done.
        defer {
            SandboxEnvironment.cleanup(tempDir: baseTempDir)
            logger.info("[wine] Cleaned up disposable WINEPREFIX at \(baseTempDir.path, privacy: .public)")
        }

        // 3. Build sandbox configuration.
        let exePath = fileURL.path
        var config = SandboxConfig.wineDefault(
            executablePath: exePath,
            winePrefix: winePrefixDir.path
        )

        // Suppress Wine's verbose debug output.
        config.environment["WINEDEBUG"] = "-all"

        logger.info("[wine] Running \(exePath, privacy: .public) with WINEPREFIX=\(winePrefixDir.path, privacy: .public)")

        // 4. Execute via SandboxExecutor.
        let result = await SandboxExecutor.execute(
            executable: winePath,
            arguments: [exePath],
            config: config,
            workingDirectory: baseTempDir.path
        )

        // 5. Log outcome.
        if result.timedOut {
            logger.warning("[wine] Execution timed out after \(String(format: "%.1f", result.elapsedSeconds))s")
        } else if result.exitCode != 0 {
            logger.warning("[wine] Exited with code \(result.exitCode) in \(String(format: "%.1f", result.elapsedSeconds))s")
        } else {
            logger.info("[wine] Completed successfully in \(String(format: "%.1f", result.elapsedSeconds))s")
        }

        return result
    }

    // MARK: - Confirmation dialog summary

    /// Lines summarising the sandbox restrictions, suitable for display in a
    /// user confirmation dialog before executing a PE file.
    static func sandboxSummary() -> [String] {
        [
            "No network access",
            "Disposable Wine environment (deleted after execution)",
            "No access to home directory or documents",
            "Memory limit: 512 MB",
            "CPU timeout: 60 seconds",
            "WARNING: Wine execution carries inherent risk",
        ]
    }

    // MARK: - Helpers

    /// Resolve a command name via `/usr/bin/which`.
    /// Returns the trimmed path on success, `nil` otherwise.
    private static func which(_ command: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [command]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        guard proc.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolved = path, !resolved.isEmpty else { return nil }

        // Verify the resolved path is actually executable.
        guard FileManager.default.isExecutableFile(atPath: resolved) else { return nil }
        return resolved
    }
}
