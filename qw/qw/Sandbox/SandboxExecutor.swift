//
//  SandboxExecutor.swift
//  qw
//
//  Core sandboxed process execution engine.  Uses macOS sandbox-exec
//  (seatbelt) profiles, resource limits, and output size caps to run
//  untrusted executables safely.
//  Ticket: T-000055
//

import Foundation
import os

// MARK: - Result

/// The outcome of a sandboxed execution.
struct SandboxResult {
    /// Process exit code (137 = killed, 124 = timeout by convention).
    let exitCode: Int32
    /// Captured standard output (truncated to `maxOutputBytes`).
    let stdout: String
    /// Captured standard error (truncated to `maxOutputBytes`).
    let stderr: String
    /// Whether the process was killed due to exceeding the time limit.
    let timedOut: Bool
    /// Whether the process was killed by the user via `kill()`.
    let killedByUser: Bool
    /// Wall-clock elapsed time in seconds.
    let elapsedSeconds: Double
}

// MARK: - Executor

/// Runs a process inside a macOS seatbelt sandbox with resource limits.
///
/// Usage:
/// ```swift
/// let config = SandboxConfig.wasmDefault
/// let result = await SandboxExecutor.execute(
///     executable: "/usr/local/bin/wasmtime",
///     arguments: ["run", "hello.wasm"],
///     config: config
/// )
/// ```
final class SandboxExecutor: @unchecked Sendable {

    private static let logger = Logger(subsystem: "com.muonium.qw", category: "sandbox")

    // MARK: - State for kill support

    /// The running process, stored so `kill()` can terminate it.
    private var process: Process?
    private let lock = NSLock()
    private var _killedByUser = false

    // MARK: - Kill

    /// Terminate the running process. Safe to call from any thread.
    /// If the process has already exited this is a no-op.
    func kill() {
        lock.lock()
        _killedByUser = true
        let proc = process
        lock.unlock()

        if let proc = proc, proc.isRunning {
            Self.logger.info("[sandbox] User requested kill for pid \(proc.processIdentifier)")
            proc.terminate()
        }
    }

    // MARK: - Execute (instance)

    /// Execute a process with the given sandbox configuration.
    /// This is the instance method that supports `kill()`.
    func run(
        executable: String,
        arguments: [String] = [],
        config: SandboxConfig,
        workingDirectory: String? = nil
    ) async -> SandboxResult {
        await Self.execute(
            executor: self,
            executable: executable,
            arguments: arguments,
            config: config,
            workingDirectory: workingDirectory
        )
    }

    // MARK: - Execute (static convenience)

    /// Execute a process with the given sandbox configuration.
    /// This static version does not support the kill button.
    static func execute(
        executable: String,
        arguments: [String] = [],
        config: SandboxConfig,
        workingDirectory: String? = nil
    ) async -> SandboxResult {
        await execute(
            executor: nil,
            executable: executable,
            arguments: arguments,
            config: config,
            workingDirectory: workingDirectory
        )
    }

    // MARK: - Core implementation

    private static func execute(
        executor: SandboxExecutor?,
        executable: String,
        arguments: [String],
        config: SandboxConfig,
        workingDirectory: String?
    ) async -> SandboxResult {

        // Validate executable exists
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            logger.error("[sandbox] Executable not found or not executable: \(executable, privacy: .public)")
            return SandboxResult(
                exitCode: -1, stdout: "", stderr: "Executable not found: \(executable)",
                timedOut: false, killedByUser: false, elapsedSeconds: 0
            )
        }

        // Create per-execution temp directory
        let tempDir: URL
        do {
            tempDir = try SandboxEnvironment.createTempDir()
        } catch {
            logger.error("[sandbox] Failed to create temp dir: \(error.localizedDescription, privacy: .public)")
            return SandboxResult(
                exitCode: -1, stdout: "", stderr: "Failed to create sandbox temp dir",
                timedOut: false, killedByUser: false, elapsedSeconds: 0
            )
        }
        defer { SandboxEnvironment.cleanup(tempDir: tempDir) }

        // Build config with TMPDIR pointing into our sandbox temp dir
        var effectiveConfig = config
        effectiveConfig.environment["TMPDIR"] = tempDir.path
        if effectiveConfig.allowFileWritePath == nil {
            effectiveConfig.allowFileWritePath = tempDir.path
        }

        // Generate seatbelt profile
        let profile = SeatbeltProfile.generate(config: effectiveConfig, executablePath: executable)

        // Write profile to a temp file so sandbox-exec can read it
        let profileURL = tempDir.appendingPathComponent("sandbox.sb")
        do {
            try profile.write(to: profileURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("[sandbox] Failed to write seatbelt profile: \(error.localizedDescription, privacy: .public)")
            return SandboxResult(
                exitCode: -1, stdout: "", stderr: "Failed to write sandbox profile",
                timedOut: false, killedByUser: false, elapsedSeconds: 0
            )
        }

        // Build the process: sandbox-exec -f <profile> <executable> <args...>
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        proc.arguments = ["-f", profileURL.path, executable] + arguments

        if let wd = workingDirectory {
            proc.currentDirectoryURL = URL(fileURLWithPath: wd)
        } else {
            proc.currentDirectoryURL = tempDir
        }

        // Sanitized environment
        proc.environment = SandboxEnvironment.sanitizedEnvironment(allowing: effectiveConfig.environment)

        // Pipes for output capture
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        // Store process reference for kill support
        if let executor = executor {
            executor.lock.lock()
            executor.process = proc
            executor.lock.unlock()
        }

        let maxBytes = config.maxOutputBytes
        let timeoutSeconds = config.cpuTimeoutSeconds

        // Execute with timeout
        let startTime = CFAbsoluteTimeGetCurrent()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<SandboxResult, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    // Launch
                    do {
                        try proc.run()
                        logger.info("[sandbox] Started pid \(proc.processIdentifier): \(executable, privacy: .public)")
                    } catch {
                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        logger.error("[sandbox] Failed to launch: \(error.localizedDescription, privacy: .public)")
                        continuation.resume(returning: SandboxResult(
                            exitCode: -1, stdout: "",
                            stderr: "Failed to launch process: \(error.localizedDescription)",
                            timedOut: false, killedByUser: false, elapsedSeconds: elapsed
                        ))
                        return
                    }

                    // Timeout watchdog
                    let timeoutItem = DispatchWorkItem {
                        if proc.isRunning {
                            logger.warning("[sandbox] Timeout (\(timeoutSeconds)s) — killing pid \(proc.processIdentifier)")
                            proc.terminate()
                            // Give it a moment, then SIGKILL if still alive
                            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                                if proc.isRunning {
                                    Darwin.kill(proc.processIdentifier, SIGKILL)
                                }
                            }
                        }
                    }
                    DispatchQueue.global().asyncAfter(
                        deadline: .now() + Double(timeoutSeconds),
                        execute: timeoutItem
                    )

                    // Read output with size limits
                    // We read on separate threads to avoid deadlock when the process
                    // fills one pipe buffer and blocks.
                    var stdoutData = Data()
                    var stderrData = Data()

                    let stdoutHandle = stdoutPipe.fileHandleForReading
                    let stderrHandle = stderrPipe.fileHandleForReading

                    let outputGroup = DispatchGroup()

                    outputGroup.enter()
                    DispatchQueue.global().async {
                        stdoutData = Self.readWithLimit(from: stdoutHandle, maxBytes: maxBytes)
                        outputGroup.leave()
                    }

                    outputGroup.enter()
                    DispatchQueue.global().async {
                        stderrData = Self.readWithLimit(from: stderrHandle, maxBytes: maxBytes)
                        outputGroup.leave()
                    }

                    proc.waitUntilExit()
                    timeoutItem.cancel()
                    outputGroup.wait()

                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    let exitCode = proc.terminationStatus

                    // Determine if timed out: the watchdog fired (was not cancelled
                    // before it ran), the process died from a signal, and enough
                    // wall-clock time passed.
                    let didTimeout = proc.terminationReason == .uncaughtSignal
                        && elapsed >= Double(timeoutSeconds) - 0.5

                    // Check user kill
                    var userKilled = false
                    if let executor = executor {
                        executor.lock.lock()
                        userKilled = executor._killedByUser
                        executor.lock.unlock()
                    }

                    let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

                    if didTimeout {
                        logger.warning("[sandbox] Process timed out after \(String(format: "%.1f", elapsed))s")
                    } else if userKilled {
                        logger.info("[sandbox] Process killed by user after \(String(format: "%.1f", elapsed))s")
                    } else {
                        logger.info("[sandbox] Process exited with code \(exitCode) in \(String(format: "%.1f", elapsed))s")
                    }

                    let result = SandboxResult(
                        exitCode: exitCode,
                        stdout: stdoutStr,
                        stderr: stderrStr,
                        timedOut: didTimeout,
                        killedByUser: userKilled,
                        elapsedSeconds: elapsed
                    )
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            if proc.isRunning {
                logger.info("[sandbox] Task cancelled — terminating pid \(proc.processIdentifier)")
                proc.terminate()
            }
        }
    }

    // MARK: - Output reading with size cap

    /// Read from a file handle up to `maxBytes`, discarding the rest.
    private static func readWithLimit(from handle: FileHandle, maxBytes: Int) -> Data {
        var accumulated = Data()
        let chunkSize = 65_536

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            let remaining = maxBytes - accumulated.count
            if remaining <= 0 {
                // Drain remaining data to avoid blocking the process, but discard it
                while !handle.readData(ofLength: chunkSize).isEmpty {}
                break
            }

            if chunk.count <= remaining {
                accumulated.append(chunk)
            } else {
                accumulated.append(chunk.prefix(remaining))
                // Drain the rest
                while !handle.readData(ofLength: chunkSize).isEmpty {}
                break
            }
        }

        return accumulated
    }
}
