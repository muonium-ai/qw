//
//  WasmRunner.swift
//  qw
//
//  Runs WebAssembly .wasm files using wasmtime (preferred) or wasmer,
//  inside a macOS seatbelt sandbox for defense in depth.
//  Ticket: T-000056
//

import Foundation
import os

/// Detects an installed WASM runtime and executes .wasm files in a sandbox.
enum WasmRunner {

    private static let logger = Logger(subsystem: "com.muonium.qw", category: "wasm")

    // MARK: - Runtime detection

    /// Well-known install locations to check before falling back to `which`.
    private static let wasmtimePaths = [
        "/opt/homebrew/bin/wasmtime",
        "/usr/local/bin/wasmtime",
    ]

    private static let wasmerPaths = [
        "/opt/homebrew/bin/wasmer",
        "/usr/local/bin/wasmer",
    ]

    /// Result of checking whether a WASM runtime is installed.
    struct Availability {
        /// Whether a usable runtime was found.
        let available: Bool
        /// The runtime name ("wasmtime" or "wasmer"), if found.
        let runtime: String?
        /// Absolute path to the runtime binary, if found.
        let binaryPath: String?
        /// Human-readable install hint when no runtime is found.
        let installHint: String?
    }

    /// Check whether wasmtime or wasmer is installed.
    static func isAvailable() -> Availability {
        // Try wasmtime first
        if let path = findBinary(candidates: wasmtimePaths, name: "wasmtime") {
            return Availability(available: true, runtime: "wasmtime", binaryPath: path, installHint: nil)
        }

        // Fall back to wasmer
        if let path = findBinary(candidates: wasmerPaths, name: "wasmer") {
            return Availability(available: true, runtime: "wasmer", binaryPath: path, installHint: nil)
        }

        return Availability(
            available: false,
            runtime: nil,
            binaryPath: nil,
            installHint: "Install wasmtime: brew install wasmtime\nOr install wasmer: curl https://get.wasmer.io -sSfL | sh"
        )
    }

    /// Look for a binary at well-known paths, then fall back to `which`.
    private static func findBinary(candidates: [String], name: String) -> String? {
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }

        // Fall back to `which`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty, fm.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {
            // `which` itself failed — ignore
        }

        return nil
    }

    // MARK: - Execution

    /// Run a .wasm file in a sandboxed WASM runtime.
    ///
    /// - Parameters:
    ///   - fileURL: URL of the .wasm file to execute.
    ///   - config: Sandbox configuration (defaults to `.wasmDefault`).
    ///   - executor: Optional `SandboxExecutor` instance to support the kill button.
    /// - Returns: The sandbox execution result.
    static func run(
        fileURL: URL,
        config: SandboxConfig = .wasmDefault,
        executor: SandboxExecutor? = nil
    ) async -> SandboxResult {
        let availability = isAvailable()

        guard let binaryPath = availability.binaryPath,
              let runtime = availability.runtime else {
            logger.error("[wasm] No WASM runtime found")
            return SandboxResult(
                exitCode: -1,
                stdout: "",
                stderr: "No WebAssembly runtime installed.\n\(availability.installHint ?? "")",
                timedOut: false,
                killedByUser: false,
                elapsedSeconds: 0
            )
        }

        let filePath = fileURL.path

        // Build runtime-specific arguments
        let arguments: [String]
        switch runtime {
        case "wasmtime":
            // wasmtime run --dir=. <file>  — grants cwd access only
            arguments = ["run", "--dir=.", filePath]
        case "wasmer":
            arguments = ["run", filePath]
        default:
            arguments = [filePath]
        }

        // Augment config to allow reading the .wasm file and the runtime binary
        var effectiveConfig = config
        effectiveConfig.allowFileReadPaths.append(filePath)
        effectiveConfig.allowFileReadPaths.append(binaryPath)
        // The runtime may need to spawn itself (wasmtime uses a child process internally)
        effectiveConfig.allowProcessSpawn = true

        logger.info("[wasm] Starting \(runtime, privacy: .public) for \(fileURL.lastPathComponent, privacy: .public)")

        let result: SandboxResult
        if let executor = executor {
            result = await executor.run(
                executable: binaryPath,
                arguments: arguments,
                config: effectiveConfig,
                workingDirectory: fileURL.deletingLastPathComponent().path
            )
        } else {
            result = await SandboxExecutor.execute(
                executable: binaryPath,
                arguments: arguments,
                config: effectiveConfig,
                workingDirectory: fileURL.deletingLastPathComponent().path
            )
        }

        if result.exitCode == 0 {
            logger.info("[wasm] \(runtime, privacy: .public) completed successfully in \(String(format: "%.1f", result.elapsedSeconds), privacy: .public)s")
        } else if result.timedOut {
            logger.warning("[wasm] \(runtime, privacy: .public) timed out after \(String(format: "%.1f", result.elapsedSeconds), privacy: .public)s")
        } else if result.killedByUser {
            logger.info("[wasm] \(runtime, privacy: .public) killed by user after \(String(format: "%.1f", result.elapsedSeconds), privacy: .public)s")
        } else {
            logger.error("[wasm] \(runtime, privacy: .public) exited with code \(result.exitCode) in \(String(format: "%.1f", result.elapsedSeconds), privacy: .public)s")
        }

        return result
    }

    // MARK: - Sandbox summary for UI

    /// Human-readable sandbox description for the confirmation dialog.
    static func sandboxSummary(config: SandboxConfig = .wasmDefault) -> [String] {
        var lines: [String] = []
        lines.append("Runtime: \(isAvailable().runtime ?? "not found")")
        lines.append("Network: \(config.allowNetwork ? "allowed" : "blocked")")
        lines.append("Filesystem: WASI sandbox (no host access by default)")
        lines.append("Memory limit: \(config.memoryLimitMB) MB")
        lines.append("CPU timeout: \(config.cpuTimeoutSeconds)s")
        lines.append("Defense in depth: macOS seatbelt sandbox")
        return lines
    }
}
