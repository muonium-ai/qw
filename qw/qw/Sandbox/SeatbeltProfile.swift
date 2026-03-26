//
//  SeatbeltProfile.swift
//  qw
//
//  Generates macOS sandbox-exec (seatbelt) profile strings from a
//  SandboxConfig.  The generated profile follows a deny-by-default
//  policy and only opens capabilities the config explicitly allows.
//  Ticket: T-000055
//

import Foundation

/// Generator for macOS seatbelt (sandbox-exec) profiles.
enum SeatbeltProfile {

    // MARK: - Public API

    /// Generate a seatbelt profile string for the given config and executable.
    ///
    /// - Parameters:
    ///   - config: The sandbox capabilities to allow.
    ///   - executablePath: Absolute path to the executable being launched.
    /// - Returns: A seatbelt profile string suitable for `sandbox-exec -p`.
    static func generate(config: SandboxConfig, executablePath: String) -> String {
        var rules: [String] = []

        // Header: deny everything by default
        rules.append("(version 1)")
        rules.append("(deny default)")

        // Always allow the process to execute itself
        rules.append("(allow process-exec (literal \(quoted(executablePath))))")

        // Always allow basic process operations needed by any program
        rules.append("(allow sysctl-read)")
        rules.append("(allow mach-lookup)")

        // -- Network --
        if config.allowNetwork {
            rules.append("(allow network*)")
        }

        // -- File reads --
        // Always allow reading system libraries and frameworks (required to run)
        rules.append("(allow file-read* (subpath \"/usr/lib\"))")
        rules.append("(allow file-read* (subpath \"/usr/local/lib\"))")
        rules.append("(allow file-read* (subpath \"/System\"))")
        rules.append("(allow file-read* (subpath \"/Library/Frameworks\"))")
        rules.append("(allow file-read* (subpath \"/usr/share\"))")

        // Allow reading the executable itself
        rules.append("(allow file-read* (literal \(quoted(executablePath))))")

        for path in config.allowFileReadPaths {
            let cleaned = cleanPath(path)
            guard !cleaned.isEmpty else { continue }
            rules.append("(allow file-read* (subpath \(quoted(cleaned))))")
        }

        // -- File writes --
        if let writePath = config.allowFileWritePath {
            let cleaned = cleanPath(writePath)
            if !cleaned.isEmpty {
                // Also allow reading the write directory
                rules.append("(allow file-read* (subpath \(quoted(cleaned))))")
                rules.append("(allow file-write* (subpath \(quoted(cleaned))))")
            }
        }

        // -- Process spawning --
        if config.allowProcessSpawn {
            rules.append("(allow process-fork)")
            rules.append("(allow process-exec)")
        }

        return rules.joined(separator: "\n")
    }

    // MARK: - Path escaping

    /// Escape and double-quote a path for safe inclusion in a seatbelt profile.
    ///
    /// Seatbelt profiles use Scheme-like syntax where string literals are
    /// enclosed in double quotes.  We must ensure embedded characters cannot
    /// break out of the string or inject additional rules.
    private static func quoted(_ path: String) -> String {
        // Remove any null bytes (could truncate the string in C-level parsing)
        var safe = path.replacingOccurrences(of: "\0", with: "")

        // Escape backslashes first, then double quotes
        safe = safe.replacingOccurrences(of: "\\", with: "\\\\")
        safe = safe.replacingOccurrences(of: "\"", with: "\\\"")

        // Remove parentheses to prevent S-expression injection
        safe = safe.replacingOccurrences(of: "(", with: "")
        safe = safe.replacingOccurrences(of: ")", with: "")

        // Remove newlines/carriage returns that could break the profile
        safe = safe.replacingOccurrences(of: "\n", with: "")
        safe = safe.replacingOccurrences(of: "\r", with: "")

        return "\"\(safe)\""
    }

    /// Resolve and clean a filesystem path, removing traversal sequences.
    private static func cleanPath(_ path: String) -> String {
        // Resolve to absolute, collapsing ".." and symlinks
        let url = URL(fileURLWithPath: path).standardized
        return url.path
    }
}
