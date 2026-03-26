//
//  SandboxEnvironment.swift
//  qw
//
//  Manages temporary directories and sanitized environment variables
//  for sandboxed process execution.
//  Ticket: T-000055
//

import Foundation
import os

/// Helpers for creating isolated execution environments.
enum SandboxEnvironment {

    private static let logger = Logger(subsystem: "com.muonium.qw", category: "sandbox")

    // MARK: - Temp directory management

    /// Create a unique temporary directory for a single execution run.
    /// The caller is responsible for calling `cleanup(tempDir:)` afterwards.
    /// - Returns: URL of the newly created directory.
    /// - Throws: If the directory cannot be created.
    static func createTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let name = "qw-sandbox-\(UUID().uuidString)"
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logger.info("[sandbox] Created temp dir: \(dir.path, privacy: .public)")
        return dir
    }

    /// Remove a temporary directory and all of its contents.
    /// Logs but does not throw on failure.
    static func cleanup(tempDir: URL) {
        do {
            if FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.removeItem(at: tempDir)
                logger.info("[sandbox] Cleaned up temp dir: \(tempDir.path, privacy: .public)")
            }
        } catch {
            logger.error("[sandbox] Failed to clean up temp dir \(tempDir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Environment sanitization

    /// Sensitive environment variable names that must never leak into sandboxed processes.
    private static let sensitiveKeys: Set<String> = [
        "HOME", "USER", "LOGNAME", "SHELL", "SSH_AUTH_SOCK",
        "SSH_AGENT_PID", "GPG_AGENT_INFO", "MAIL",
        "DISPLAY", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS",
        "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
        "GITHUB_TOKEN", "GH_TOKEN", "HOMEBREW_GITHUB_API_TOKEN",
        "OPENAI_API_KEY", "ANTHROPIC_API_KEY",
        "TERM_SESSION_ID", "TERM_PROGRAM", "ITERM_SESSION_ID",
        "Apple_PubSub_Socket_Render", "SECURITYSESSIONID",
    ]

    /// Build a minimal, sanitized environment dictionary.
    /// - Parameter additional: Extra variables to merge (from `SandboxConfig.environment`).
    ///   Keys in `sensitiveKeys` are silently dropped even if passed here.
    /// - Returns: A dictionary safe to pass to `Process.environment`.
    static func sanitizedEnvironment(allowing additional: [String: String] = [:]) -> [String: String] {
        var env: [String: String] = [
            "PATH": "/usr/bin:/usr/local/bin",
            "LANG": "en_US.UTF-8",
        ]

        for (key, value) in additional {
            guard !sensitiveKeys.contains(key) else {
                logger.warning("[sandbox] Dropping sensitive env var: \(key, privacy: .public)")
                continue
            }
            env[key] = value
        }

        return env
    }
}
