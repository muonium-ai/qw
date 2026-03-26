//
//  NativeRunner.swift
//  qw
//
//  Runner for native Mach-O and ELF executables using macOS sandbox-exec
//  with strict seatbelt profiles. ELF on macOS is handled gracefully with
//  clear messaging about limitations.
//  Ticket: T-000057
//

import Foundation
import os

/// Runs native Mach-O and ELF executables inside a seatbelt sandbox.
enum NativeRunner {

    private static let logger = Logger(subsystem: "com.muonium.qw", category: "native-runner")

    // MARK: - Format names recognised as native executables

    /// All Mach-O variant names as they appear in MagicBytes / FormatDatabase.
    private static let machOFormats: Set<String> = [
        "Mach-O Universal Binary",
        "Mach-O (32-bit)",
        "Mach-O (64-bit)",
        "Mach-O (64-bit, reversed)",
        "Mach-O (32-bit, reversed)",
    ]

    /// ELF format name.
    private static let elfFormat = "ELF Executable"

    // MARK: - Capability check

    /// Returns `true` when `formatName` identifies a Mach-O variant or ELF binary.
    static func canRun(formatName: String) -> Bool {
        machOFormats.contains(formatName) || formatName == elfFormat
    }

    // MARK: - Runtime info

    /// Returns whether the format can run on this host together with an
    /// optional user-facing hint when it cannot.
    static func runtimeInfo(formatName: String) -> (canRun: Bool, hint: String?) {
        guard canRun(formatName: formatName) else {
            return (false, "Not a native executable format.")
        }

        if machOFormats.contains(formatName) {
            return (true, nil)
        }

        // ELF on macOS — check for available emulators
        if isRosettaAvailable() {
            // Rosetta translates x86_64 Mach-O, not ELF.
            // It won't help here, but mention it for clarity.
        }

        if isQemuUserAvailable() {
            return (true, "ELF will run via qemu-user emulation (may be slow).")
        }

        return (
            false,
            "ELF executables require Linux. Install qemu-user "
            + "(e.g. `brew install qemu`) to run ELF binaries on macOS."
        )
    }

    // MARK: - Sandbox summary (for confirmation dialog)

    /// Human-readable summary of the sandbox restrictions applied to native
    /// execution.  Intended for display in a confirmation dialog before running.
    static var sandboxSummary: [String] {
        [
            "No network access",
            "Read-only filesystem (executable only)",
            "Write access limited to temporary directory",
            "No process spawning",
            "Memory limit: 512 MB",
            "CPU timeout: 30 seconds",
            "Process will be killed if limits exceeded",
        ]
    }

    // MARK: - Execute

    /// Run a native executable inside a strict seatbelt sandbox.
    ///
    /// - Parameter fileURL: URL of the Mach-O or ELF binary to execute.
    /// - Returns: A `SandboxResult` with stdout/stderr, exit code, and timing.
    static func run(fileURL: URL) async -> SandboxResult {
        let path = fileURL.path

        // Detect format to decide execution strategy
        let formatName = detectFormat(at: fileURL)
        logger.info("[native-runner] Running \(path, privacy: .public) (format: \(formatName ?? "unknown", privacy: .public))")

        guard let formatName = formatName, canRun(formatName: formatName) else {
            logger.error("[native-runner] Unrecognised or unsupported format for: \(path, privacy: .public)")
            FormatLogger.logOpenFailure(
                fileURL: fileURL, formatName: formatName, mode: "execute",
                error: "Not a recognised native executable"
            )
            return SandboxResult(
                exitCode: -1, stdout: "",
                stderr: "Not a recognised native executable format.",
                timedOut: false, killedByUser: false, elapsedSeconds: 0
            )
        }

        // ELF on macOS — check feasibility
        if formatName == elfFormat {
            let info = runtimeInfo(formatName: formatName)
            if !info.canRun {
                logger.warning("[native-runner] ELF cannot run on this host")
                FormatLogger.logOpenFailure(
                    fileURL: fileURL, formatName: formatName, mode: "execute",
                    error: info.hint ?? "ELF not supported on macOS"
                )
                return SandboxResult(
                    exitCode: -1, stdout: "",
                    stderr: info.hint ?? "ELF executables cannot run on macOS without an emulator.",
                    timedOut: false, killedByUser: false, elapsedSeconds: 0
                )
            }
        }

        // Create temp directory for the execution
        let tempDir: URL
        do {
            tempDir = try SandboxEnvironment.createTempDir()
        } catch {
            logger.error("[native-runner] Failed to create temp dir: \(error.localizedDescription, privacy: .public)")
            return SandboxResult(
                exitCode: -1, stdout: "",
                stderr: "Failed to create sandbox temporary directory.",
                timedOut: false, killedByUser: false, elapsedSeconds: 0
            )
        }
        defer { SandboxEnvironment.cleanup(tempDir: tempDir) }

        // Ensure the executable has +x permission
        do {
            try ensureExecutable(at: path)
        } catch {
            logger.error("[native-runner] Failed to set +x on \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return SandboxResult(
                exitCode: -1, stdout: "",
                stderr: "Failed to set executable permission: \(error.localizedDescription)",
                timedOut: false, killedByUser: false, elapsedSeconds: 0
            )
        }

        // Build sandbox config
        let config = SandboxConfig.nativeDefault(
            executablePath: path,
            tmpDir: tempDir.path
        )

        // Determine executable and arguments
        let executablePath: String
        let arguments: [String]

        if formatName == elfFormat {
            // ELF via qemu-user
            guard let qemuPath = qemuUserPath() else {
                return SandboxResult(
                    exitCode: -1, stdout: "",
                    stderr: "qemu-user not found. Install with: brew install qemu",
                    timedOut: false, killedByUser: false, elapsedSeconds: 0
                )
            }
            executablePath = qemuPath
            arguments = [path]
            logger.info("[native-runner] Using qemu-user at \(qemuPath, privacy: .public) for ELF")
        } else {
            // Mach-O: execute directly
            executablePath = path
            arguments = []
        }

        // Execute in sandbox
        logger.info("[native-runner] Launching in sandbox: \(executablePath, privacy: .public)")
        let result = await SandboxExecutor.execute(
            executable: executablePath,
            arguments: arguments,
            config: config,
            workingDirectory: tempDir.path
        )

        // Log outcome
        if result.exitCode == 0 {
            FormatLogger.logOpenSuccess(fileURL: fileURL, formatName: formatName, mode: "execute")
        } else {
            let reason: String
            if result.timedOut {
                reason = "Timed out after \(String(format: "%.1f", result.elapsedSeconds))s"
            } else if result.killedByUser {
                reason = "Killed by user"
            } else {
                reason = "Exit code \(result.exitCode)"
            }
            FormatLogger.logOpenFailure(
                fileURL: fileURL, formatName: formatName, mode: "execute", error: reason
            )
        }

        return result
    }

    // MARK: - Helpers (private)

    /// Detect the format name of the file at the given URL by reading magic bytes.
    private static func detectFormat(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }

        let headerData = handle.readData(ofLength: 32)
        guard !headerData.isEmpty else { return nil }

        return MagicBytes.detect(from: headerData)?.name
    }

    /// Ensure the file at `path` has the executable bit set.
    /// If the file is already executable this is a no-op.
    private static func ensureExecutable(at path: String) throws {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: path)
        guard let perms = attrs[.posixPermissions] as? Int else { return }

        // Check if owner-execute is set
        let ownerExecute = 0o100
        if perms & ownerExecute == 0 {
            let newPerms = perms | ownerExecute
            try fm.setAttributes([.posixPermissions: newPerms], ofItemAtPath: path)
            logger.info("[native-runner] Set +x on \(path, privacy: .public) (\(String(perms, radix: 8)) -> \(String(newPerms, radix: 8)))")
        }
    }

    /// Check whether Rosetta 2 is installed (for reference; Rosetta translates
    /// x86_64 Mach-O, not ELF, but the check is useful for diagnostics).
    private static func isRosettaAvailable() -> Bool {
        // /usr/libexec/rosetta/oahd is the Rosetta daemon
        FileManager.default.fileExists(atPath: "/usr/libexec/rosetta/oahd")
    }

    /// Check whether qemu-user-static or qemu-x86_64 is available.
    private static func isQemuUserAvailable() -> Bool {
        qemuUserPath() != nil
    }

    /// Returns the path to a usable qemu-user binary, or nil.
    private static func qemuUserPath() -> String? {
        let candidates = [
            "/usr/local/bin/qemu-x86_64",
            "/opt/homebrew/bin/qemu-x86_64",
            "/usr/local/bin/qemu-aarch64",
            "/opt/homebrew/bin/qemu-aarch64",
            "/usr/local/bin/qemu-x86_64-static",
            "/opt/homebrew/bin/qemu-x86_64-static",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
