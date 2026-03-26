//
//  SandboxConfig.swift
//  qw
//
//  Capability-based sandbox configuration for secure process execution.
//  All executable runners (native, WASM, Wine, JVM) use this to declare
//  the minimum permissions they need.
//  Ticket: T-000055
//

import Foundation

/// Capability-based permissions for a sandboxed process execution.
struct SandboxConfig {

    // MARK: - Capabilities

    /// Whether the process may access the network.
    var allowNetwork: Bool = false

    /// Specific filesystem paths the process may read.
    var allowFileReadPaths: [String] = []

    /// Single directory the process may write to (typically a temp dir).
    var allowFileWritePath: String? = nil

    /// Whether the process may spawn child processes.
    var allowProcessSpawn: Bool = false

    // MARK: - Resource limits

    /// Maximum resident memory in megabytes.
    var memoryLimitMB: Int = 256

    /// Maximum wall-clock time before the process is killed.
    var cpuTimeoutSeconds: Int = 30

    /// Maximum combined stdout + stderr bytes captured (excess is truncated).
    var maxOutputBytes: Int = 1_048_576  // 1 MB

    // MARK: - Environment

    /// Additional environment variables passed to the process.
    /// These are merged into the sanitized base environment.
    var environment: [String: String] = [:]

    // MARK: - Presets

    /// Default sandbox for WebAssembly runtimes.
    /// No filesystem, no network, no spawn.
    static let wasmDefault = SandboxConfig(
        allowNetwork: false,
        allowFileReadPaths: [],
        allowFileWritePath: nil,
        allowProcessSpawn: false,
        memoryLimitMB: 256,
        cpuTimeoutSeconds: 30,
        maxOutputBytes: 1_048_576,
        environment: [:]
    )

    /// Default sandbox for native executables.
    /// Read-only access to the executable, temp dir for writes, no network/spawn.
    static func nativeDefault(executablePath: String, tmpDir: String) -> SandboxConfig {
        SandboxConfig(
            allowNetwork: false,
            allowFileReadPaths: [executablePath],
            allowFileWritePath: tmpDir,
            allowProcessSpawn: false,
            memoryLimitMB: 512,
            cpuTimeoutSeconds: 30,
            maxOutputBytes: 1_048_576,
            environment: [:]
        )
    }

    /// Default sandbox for Wine (Windows PE) execution.
    /// WINEPREFIX is the only writable path; longer timeout for Wine startup.
    static func wineDefault(executablePath: String, winePrefix: String) -> SandboxConfig {
        SandboxConfig(
            allowNetwork: false,
            allowFileReadPaths: [executablePath, winePrefix],
            allowFileWritePath: winePrefix,
            allowProcessSpawn: false,
            memoryLimitMB: 512,
            cpuTimeoutSeconds: 60,
            maxOutputBytes: 1_048_576,
            environment: ["WINEPREFIX": winePrefix]
        )
    }

    /// Default sandbox for JVM execution.
    /// Read-only jar, temp dir for writes, no network/spawn.
    static func jvmDefault(jarPath: String, tmpDir: String) -> SandboxConfig {
        SandboxConfig(
            allowNetwork: false,
            allowFileReadPaths: [jarPath],
            allowFileWritePath: tmpDir,
            allowProcessSpawn: false,
            memoryLimitMB: 256,
            cpuTimeoutSeconds: 30,
            maxOutputBytes: 1_048_576,
            environment: [:]
        )
    }
}
