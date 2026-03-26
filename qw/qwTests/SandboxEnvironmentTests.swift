//
//  SandboxEnvironmentTests.swift
//  qwTests
//
//  Unit tests for SandboxEnvironment
//

#if os(macOS)

import XCTest
@testable import qw

final class SandboxEnvironmentTests: XCTestCase {

    // MARK: - Temp directory lifecycle helpers

    private var tempDirs: [URL] = []

    override func setUp() {
        super.setUp()
        tempDirs = []
    }

    override func tearDown() {
        for dir in tempDirs {
            SandboxEnvironment.cleanup(tempDir: dir)
        }
        tempDirs = []
        super.tearDown()
    }

    // MARK: - 1. Default environment

    func testDefaultEnvironmentContainsExactlyPathAndLang() {
        let env = SandboxEnvironment.sanitizedEnvironment()
        XCTAssertEqual(env.count, 2, "Default environment should contain exactly 2 keys")
        XCTAssertNotNil(env["PATH"])
        XCTAssertNotNil(env["LANG"])
    }

    func testDefaultPathValue() {
        let env = SandboxEnvironment.sanitizedEnvironment()
        XCTAssertEqual(env["PATH"], "/usr/bin:/usr/local/bin")
    }

    func testDefaultLangValue() {
        let env = SandboxEnvironment.sanitizedEnvironment()
        XCTAssertEqual(env["LANG"], "en_US.UTF-8")
    }

    // MARK: - 2. Sensitive key stripping

    /// Every sensitive key that must be stripped.
    private static let allSensitiveKeys: [String] = [
        "HOME", "USER", "LOGNAME", "SHELL", "SSH_AUTH_SOCK",
        "SSH_AGENT_PID", "GPG_AGENT_INFO", "MAIL",
        "DISPLAY", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS",
        "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
        "GITHUB_TOKEN", "GH_TOKEN", "HOMEBREW_GITHUB_API_TOKEN",
        "OPENAI_API_KEY", "ANTHROPIC_API_KEY",
        "TERM_SESSION_ID", "TERM_PROGRAM", "ITERM_SESSION_ID",
        "Apple_PubSub_Socket_Render", "SECURITYSESSIONID",
    ]

    func testEachSensitiveKeyIsStrippedIndividually() {
        for key in Self.allSensitiveKeys {
            let env = SandboxEnvironment.sanitizedEnvironment(allowing: [key: "leaked"])
            XCTAssertNil(env[key], "Sensitive key '\(key)' should be stripped from output")
        }
    }

    func testAllSensitiveKeysStrippedInBatch() {
        var additional: [String: String] = [:]
        for key in Self.allSensitiveKeys {
            additional[key] = "leaked-\(key)"
        }
        let env = SandboxEnvironment.sanitizedEnvironment(allowing: additional)
        for key in Self.allSensitiveKeys {
            XCTAssertNil(env[key], "Sensitive key '\(key)' should not be present when passed in batch")
        }
        // Only PATH and LANG should survive
        XCTAssertEqual(env.count, 2)
    }

    func testSensitiveKeysCannotOverrideDefaults() {
        // PATH and LANG are defaults; passing them as sensitive shouldn't matter,
        // but passing sensitive keys with the same value as defaults should not
        // cause defaults to disappear. Also verify a sensitive key named "PATH"
        // is NOT in the sensitive list, so PATH stays.
        let env = SandboxEnvironment.sanitizedEnvironment(allowing: [
            "HOME": "/evil",
            "ANTHROPIC_API_KEY": "sk-secret",
        ])
        XCTAssertNil(env["HOME"])
        XCTAssertNil(env["ANTHROPIC_API_KEY"])
        XCTAssertEqual(env["PATH"], "/usr/bin:/usr/local/bin", "Defaults must survive even when sensitive keys are passed")
        XCTAssertEqual(env["LANG"], "en_US.UTF-8")
    }

    // MARK: - 3. Safe key passthrough

    func testSafeKeysPassThrough() {
        let env = SandboxEnvironment.sanitizedEnvironment(allowing: [
            "WINEPREFIX": "/home/wine",
            "MY_CUSTOM_VAR": "hello",
        ])
        XCTAssertEqual(env["WINEPREFIX"], "/home/wine")
        XCTAssertEqual(env["MY_CUSTOM_VAR"], "hello")
        // Defaults still present
        XCTAssertEqual(env["PATH"], "/usr/bin:/usr/local/bin")
        XCTAssertEqual(env["LANG"], "en_US.UTF-8")
        XCTAssertEqual(env.count, 4)
    }

    func testMixedSensitiveAndSafeKeys() {
        let env = SandboxEnvironment.sanitizedEnvironment(allowing: [
            "AWS_SECRET_ACCESS_KEY": "AKIA-secret",
            "GITHUB_TOKEN": "ghp_xxx",
            "BUILD_NUMBER": "42",
            "CI": "true",
        ])
        // Sensitive keys stripped
        XCTAssertNil(env["AWS_SECRET_ACCESS_KEY"])
        XCTAssertNil(env["GITHUB_TOKEN"])
        // Safe keys present
        XCTAssertEqual(env["BUILD_NUMBER"], "42")
        XCTAssertEqual(env["CI"], "true")
        // Defaults + 2 safe keys
        XCTAssertEqual(env.count, 4)
    }

    // MARK: - 4. Temp directory lifecycle

    func testCreateTempDirCreatesExistingDirectory() throws {
        let dir = try SandboxEnvironment.createTempDir()
        tempDirs.append(dir)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: dir.path),
            "createTempDir() should create a directory that exists on disk"
        )
    }

    func testTempDirNamePrefix() throws {
        let dir = try SandboxEnvironment.createTempDir()
        tempDirs.append(dir)
        XCTAssertTrue(
            dir.lastPathComponent.hasPrefix("qw-sandbox-"),
            "Temp directory name should start with 'qw-sandbox-', got: \(dir.lastPathComponent)"
        )
    }

    func testCleanupRemovesDirectory() throws {
        let dir = try SandboxEnvironment.createTempDir()
        // Don't add to tempDirs — we clean up manually here
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        SandboxEnvironment.cleanup(tempDir: dir)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dir.path),
            "cleanup() should remove the directory"
        )
    }

    func testCleanupOnNonExistentPathDoesNotCrash() {
        let bogus = URL(fileURLWithPath: "/tmp/qw-sandbox-does-not-exist-\(UUID().uuidString)")
        // Should not throw or crash
        SandboxEnvironment.cleanup(tempDir: bogus)
    }

    // MARK: - 5. Multiple temp directories are unique

    func testMultipleTempDirsAreUnique() throws {
        let dir1 = try SandboxEnvironment.createTempDir()
        tempDirs.append(dir1)
        let dir2 = try SandboxEnvironment.createTempDir()
        tempDirs.append(dir2)
        XCTAssertNotEqual(dir1.path, dir2.path, "Each call to createTempDir() should produce a unique path")
    }
}

#endif
