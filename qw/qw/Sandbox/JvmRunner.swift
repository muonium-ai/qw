//
//  JvmRunner.swift
//  qw
//
//  Runner for JAR files using the Java runtime with SecurityManager
//  restrictions, wrapped in the sandbox framework for defense-in-depth.
//  Ticket: T-000059
//

import Foundation
import os

/// Runs Java JAR files inside a dual-layered sandbox: macOS seatbelt at the
/// OS level and Java SecurityManager at the JVM level.
enum JvmRunner {

    private static let logger = Logger(subsystem: "com.muonium.qw", category: "jvm")

    // MARK: - Java discovery

    /// Well-known paths where Java may be installed on macOS.
    private static let wellKnownPaths: [String] = [
        "/usr/bin/java",
        "/usr/local/bin/java",
        "/opt/homebrew/bin/java",
    ]

    /// Check whether Java is available on this system.
    ///
    /// - Returns: A tuple indicating availability, the resolved Java binary
    ///   path (if found), the version string, and a human-readable install hint
    ///   (if not found).
    static func isAvailable() -> (available: Bool, javaPath: String?, version: String?, installHint: String?) {
        let fm = FileManager.default

        // Check well-known locations first.
        for path in wellKnownPaths {
            if fm.isExecutableFile(atPath: path) {
                let version = javaVersion(at: path)
                logger.info("[jvm] Found Java at \(path, privacy: .public)")
                return (available: true, javaPath: path, version: version, installHint: nil)
            }
        }

        // Fall back to `which java`.
        if let resolved = which("java") {
            let version = javaVersion(at: resolved)
            logger.info("[jvm] Found Java via which: \(resolved, privacy: .public)")
            return (available: true, javaPath: resolved, version: version, installHint: nil)
        }

        logger.info("[jvm] Java not found on this system")
        return (
            available: false,
            javaPath: nil,
            version: nil,
            installHint: "Install Java via: brew install openjdk"
        )
    }

    // MARK: - JAR file detection

    /// Check whether the given URL points to a JAR file.
    ///
    /// Verifies both the `.jar` file extension and that the file starts with
    /// the ZIP magic bytes (`PK`, 0x50 0x4B) since JARs are ZIP archives.
    static func isJarFile(url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "jar" else { return false }

        // Verify ZIP magic bytes (PK\x03\x04 or PK\x05\x06 for empty).
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        let header = handle.readData(ofLength: 4)
        guard header.count >= 2 else { return false }

        let pk: [UInt8] = [0x50, 0x4B]
        return header[header.startIndex] == pk[0] && header[header.startIndex + 1] == pk[1]
    }

    // MARK: - Execution

    /// Run a JAR file inside a dual-layered sandbox.
    ///
    /// Outer layer: macOS seatbelt (via SandboxExecutor).
    /// Inner layer: Java SecurityManager with a restrictive policy file.
    ///
    /// - Parameter fileURL: URL of the `.jar` file to execute.
    /// - Returns: A `SandboxResult` with captured stdout/stderr and exit info.
    static func run(fileURL: URL) async -> SandboxResult {
        // 1. Verify Java is available.
        let availability = isAvailable()
        guard let javaPath = availability.javaPath else {
            let hint = availability.installHint ?? "Java is not installed."
            logger.error("[jvm] Cannot run — Java not found")
            FormatLogger.logOpenFailure(
                fileURL: fileURL,
                formatName: "Java JAR",
                mode: "jvm",
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

        // 2. Create a disposable temp directory.
        let tempDir: URL
        do {
            tempDir = try SandboxEnvironment.createTempDir()
        } catch {
            let msg = "Failed to create temp directory: \(error.localizedDescription)"
            logger.error("[jvm] \(msg, privacy: .public)")
            return SandboxResult(
                exitCode: -1,
                stdout: "",
                stderr: msg,
                timedOut: false,
                killedByUser: false,
                elapsedSeconds: 0
            )
        }

        defer {
            SandboxEnvironment.cleanup(tempDir: tempDir)
            logger.info("[jvm] Cleaned up temp dir at \(tempDir.path, privacy: .public)")
        }

        // 3. Generate a restrictive Java security policy file.
        let jarPath = fileURL.path
        let policyContent = generateSecurityPolicy(jarPath: jarPath, tmpDir: tempDir.path)
        let policyURL = tempDir.appendingPathComponent("sandbox.policy")

        do {
            try policyContent.write(to: policyURL, atomically: true, encoding: .utf8)
        } catch {
            let msg = "Failed to write Java security policy: \(error.localizedDescription)"
            logger.error("[jvm] \(msg, privacy: .public)")
            return SandboxResult(
                exitCode: -1,
                stdout: "",
                stderr: msg,
                timedOut: false,
                killedByUser: false,
                elapsedSeconds: 0
            )
        }

        // 4. Build sandbox configuration.
        let config = SandboxConfig.jvmDefault(jarPath: jarPath, tmpDir: tempDir.path)

        // 5. Build Java arguments.
        //    - SecurityManager flags (deprecated in 17+ but functional with allow flag)
        //    - Double-equals on policy means ONLY this policy, replacing defaults
        //    - Heap limit via -Xmx
        var javaArgs: [String] = []

        // Detect Java major version for SecurityManager compatibility.
        let majorVersion = javaMajorVersion(from: availability.version)
        if majorVersion >= 17 {
            // Java 17+ requires explicit opt-in for SecurityManager.
            javaArgs.append("-Djava.security.manager=allow")
        }

        javaArgs.append(contentsOf: [
            "-Xmx256m",
            "-Djava.security.manager",
            "-Djava.security.policy==\(policyURL.path)",
            "-jar",
            jarPath,
        ])

        logger.info("[jvm] Running \(jarPath, privacy: .public) with Java at \(javaPath, privacy: .public)")

        // 6. Execute via SandboxExecutor (seatbelt as outer layer).
        let result = await SandboxExecutor.execute(
            executable: javaPath,
            arguments: javaArgs,
            config: config,
            workingDirectory: tempDir.path
        )

        // 7. Log outcome.
        if result.timedOut {
            logger.warning("[jvm] Execution timed out after \(String(format: "%.1f", result.elapsedSeconds))s")
        } else if result.exitCode != 0 {
            logger.warning("[jvm] Exited with code \(result.exitCode) in \(String(format: "%.1f", result.elapsedSeconds))s")
        } else {
            logger.info("[jvm] Completed successfully in \(String(format: "%.1f", result.elapsedSeconds))s")
        }

        return result
    }

    // MARK: - Confirmation dialog summary

    /// Lines summarising the sandbox restrictions, suitable for display in a
    /// user confirmation dialog before executing a JAR file.
    static func sandboxSummary() -> [String] {
        [
            "No network access (Java SecurityManager + seatbelt)",
            "No file access outside temporary directory",
            "No process execution from within Java",
            "No native library loading",
            "Heap limit: 256 MB (-Xmx256m)",
            "CPU timeout: 30 seconds",
            "Defense in depth: Java SecurityManager + macOS seatbelt",
        ]
    }

    // MARK: - Security policy generation

    /// Generate a Java security policy that:
    /// - Allows read/write/delete inside the temp directory
    /// - Allows read-only access to the JAR itself
    /// - Allows reading system properties
    /// - Denies everything else (network, exec, other file paths, native libs)
    private static func generateSecurityPolicy(jarPath: String, tmpDir: String) -> String {
        """
        // Auto-generated Java security policy for qw sandbox.
        // Denies all permissions except those explicitly granted below.

        grant {
            permission java.io.FilePermission "\(tmpDir)/-", "read,write,delete";
            permission java.io.FilePermission "\(jarPath)", "read";
            permission java.util.PropertyPermission "*", "read";
        };
        """
    }

    // MARK: - Helpers

    /// Run `java -version` and return the version output string.
    /// Java prints version info to stderr, not stdout.
    private static func javaVersion(at javaPath: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: javaPath)
        proc.arguments = ["-version"]

        let pipe = Pipe()
        // java -version writes to stderr
        proc.standardError = pipe
        proc.standardOutput = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        guard proc.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let version = output, !version.isEmpty else { return nil }
        return version
    }

    /// Extract the major version number from a `java -version` output string.
    ///
    /// Handles both old-style (`1.8.0_xxx` -> 8) and new-style (`17.0.2` -> 17).
    /// Returns 0 if the version cannot be parsed.
    private static func javaMajorVersion(from versionString: String?) -> Int {
        guard let versionString = versionString else { return 0 }

        // Look for a quoted version string like "17.0.2" or "1.8.0_362"
        let pattern = #""(\d+)(?:\.(\d+))?[^"]*""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: versionString,
                  range: NSRange(versionString.startIndex..., in: versionString)
              ) else {
            return 0
        }

        guard let majorRange = Range(match.range(at: 1), in: versionString),
              let major = Int(versionString[majorRange]) else {
            return 0
        }

        // Old-style versioning: "1.8.0" means Java 8
        if major == 1, match.range(at: 2).location != NSNotFound,
           let minorRange = Range(match.range(at: 2), in: versionString),
           let minor = Int(versionString[minorRange]) {
            return minor
        }

        return major
    }

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
