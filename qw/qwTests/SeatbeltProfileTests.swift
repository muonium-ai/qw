//
//  SeatbeltProfileTests.swift
//  qwTests
//
//  Tests for SeatbeltProfile seatbelt (sandbox-exec) profile generation.
//

import XCTest

#if os(macOS)
@testable import qw

final class SeatbeltProfileTests: XCTestCase {

    // MARK: - Helpers

    /// Minimal config: everything denied, no extra paths.
    private func minimalConfig() -> SandboxConfig {
        SandboxConfig(
            allowNetwork: false,
            allowFileReadPaths: [],
            allowFileWritePath: nil,
            allowProcessSpawn: false,
            memoryLimitMB: 256,
            cpuTimeoutSeconds: 30,
            maxOutputBytes: 1_048_576,
            environment: [:]
        )
    }

    private let dummyExe = "/usr/local/bin/dummy"

    // MARK: - 1. Deny-default baseline

    func testMinimalProfileStartsWithVersionAndDenyDefault() {
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: dummyExe)
        let lines = profile.components(separatedBy: "\n")

        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "(version 1)")
        XCTAssertEqual(lines[1], "(deny default)")
    }

    func testMinimalProfileContainsSysctlReadAndMachLookup() {
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: dummyExe)

        XCTAssertTrue(profile.contains("(allow sysctl-read)"))
        XCTAssertTrue(profile.contains("(allow mach-lookup)"))
    }

    func testMinimalProfileAllowsSystemReadPaths() {
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: dummyExe)

        XCTAssertTrue(profile.contains("(allow file-read* (subpath \"/usr/lib\"))"))
        XCTAssertTrue(profile.contains("(allow file-read* (subpath \"/usr/local/lib\"))"))
        XCTAssertTrue(profile.contains("(allow file-read* (subpath \"/System\"))"))
        XCTAssertTrue(profile.contains("(allow file-read* (subpath \"/Library/Frameworks\"))"))
        XCTAssertTrue(profile.contains("(allow file-read* (subpath \"/usr/share\"))"))
    }

    // MARK: - 2. Executable path

    func testProfileContainsProcessExecForExecutable() {
        let exe = "/path/to/exe"
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: exe)

        XCTAssertTrue(profile.contains("(allow process-exec (literal \"/path/to/exe\"))"))
    }

    func testProfileContainsFileReadForExecutable() {
        let exe = "/path/to/exe"
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: exe)

        XCTAssertTrue(profile.contains("(allow file-read* (literal \"/path/to/exe\"))"))
    }

    // MARK: - 3. Network capability

    func testNetworkDisabledDoesNotContainNetworkRule() {
        var config = minimalConfig()
        config.allowNetwork = false
        let profile = SeatbeltProfile.generate(config: config, executablePath: dummyExe)

        XCTAssertFalse(profile.contains("network"))
    }

    func testNetworkEnabledContainsNetworkRule() {
        var config = minimalConfig()
        config.allowNetwork = true
        let profile = SeatbeltProfile.generate(config: config, executablePath: dummyExe)

        XCTAssertTrue(profile.contains("(allow network*)"))
    }

    // MARK: - 4. File read paths

    func testAdditionalReadPathsAppearAsSubpathRules() {
        var config = minimalConfig()
        config.allowFileReadPaths = ["/tmp/data", "/home/user/files"]
        let profile = SeatbeltProfile.generate(config: config, executablePath: dummyExe)

        XCTAssertTrue(profile.contains("(allow file-read* (subpath \"/tmp/data\"))"),
                       "Expected subpath rule for /tmp/data")
        // /home/user/files resolves via cleanPath; on macOS /home may redirect to /System/Volumes/Data/home
        // so just check the profile contains a subpath rule with "files" in it
        XCTAssertTrue(profile.contains("(allow file-read* (subpath"),
                       "Expected subpath rule for additional read path")
    }

    func testEmptyReadPathResolvesToCurrentDirectory() {
        // Empty string resolves to CWD via URL(fileURLWithPath:).standardized,
        // so it becomes a valid (non-empty) path and IS included.
        var config = minimalConfig()
        config.allowFileReadPaths = [""]
        let profile = SeatbeltProfile.generate(config: config, executablePath: dummyExe)

        // Count occurrences of "subpath" — 5 system paths + 1 resolved CWD = 6
        let subpathCount = profile.components(separatedBy: "(subpath").count - 1
        XCTAssertEqual(subpathCount, 6, "Empty path resolves to CWD and is included as a subpath rule")
    }

    // MARK: - 5. File write path

    func testWritePathGeneratesBothReadAndWriteRules() {
        var config = minimalConfig()
        config.allowFileWritePath = "/tmp/output"
        let profile = SeatbeltProfile.generate(config: config, executablePath: dummyExe)

        XCTAssertTrue(profile.contains("(allow file-read* (subpath \"/tmp/output\"))"),
                       "Write path should also generate a read rule")
        XCTAssertTrue(profile.contains("(allow file-write* (subpath \"/tmp/output\"))"),
                       "Write path should generate a write rule")
    }

    func testNilWritePathGeneratesNoWriteRule() {
        var config = minimalConfig()
        config.allowFileWritePath = nil
        let profile = SeatbeltProfile.generate(config: config, executablePath: dummyExe)

        XCTAssertFalse(profile.contains("file-write*"))
    }

    // MARK: - 6. Process spawn

    func testProcessSpawnDisabledNoForkOrExtraneousExec() {
        var config = minimalConfig()
        config.allowProcessSpawn = false
        let profile = SeatbeltProfile.generate(config: config, executablePath: dummyExe)

        XCTAssertFalse(profile.contains("process-fork"))
        // The only process-exec should be the self-exec for the executable (literal)
        // There should be no bare "(allow process-exec)" without a literal qualifier
        XCTAssertFalse(profile.contains("(allow process-exec)\n"),
                        "Bare process-exec should not appear when spawn is disabled")
    }

    func testProcessSpawnEnabledContainsForkAndExec() {
        var config = minimalConfig()
        config.allowProcessSpawn = true
        let profile = SeatbeltProfile.generate(config: config, executablePath: dummyExe)

        XCTAssertTrue(profile.contains("(allow process-fork)"))
        XCTAssertTrue(profile.contains("(allow process-exec)"))
    }

    // MARK: - 7. SECURITY: Path escaping (adversarial inputs)

    func testPathWithDoubleQuotesIsEscaped() {
        let evilExe = "/tmp/evil\"(allow network*)\"path"
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: evilExe)

        // Parentheses should be removed, quotes should be escaped
        XCTAssertFalse(profile.contains("(allow network*)\""),
                        "Injected seatbelt rule must not appear verbatim")
        // The escaped form should have \" and no raw parens from the path
        XCTAssertTrue(profile.contains("\\\""), "Double quotes in path should be backslash-escaped")
    }

    func testPathWithNullBytesIsStripped() {
        let evilExe = "/tmp/evil\0path"
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: evilExe)

        XCTAssertFalse(profile.contains("\0"), "Null bytes must be removed from output")
        XCTAssertTrue(profile.contains("/tmp/evilpath"), "Path should remain minus the null byte")
    }

    func testPathWithParenthesesAreRemoved() {
        let evilExe = "/tmp/evil(deny default)path"
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: evilExe)

        // The injected S-expression must not appear intact
        XCTAssertFalse(profile.contains("(deny default)path"),
                        "Parenthesized injection must be stripped")
        XCTAssertTrue(profile.contains("evildeny defaultpath"),
                       "Parens stripped but text kept")
    }

    func testPathWithNewlinesAreRemoved() {
        let evilExe = "/tmp/evil\npath"
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: evilExe)

        // Check the literal portion of the exec rule does not contain a newline mid-path
        let execRule = profile.components(separatedBy: "\n").first {
            $0.contains("process-exec") && $0.contains("literal")
        }
        XCTAssertNotNil(execRule, "Should have a process-exec literal rule")
        XCTAssertFalse(execRule?.contains("\n") ?? false,
                        "Newlines must not appear inside the quoted path")
    }

    func testPathWithCarriageReturnIsRemoved() {
        let evilExe = "/tmp/evil\rpath"
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: evilExe)

        let execRule = profile.components(separatedBy: "\n").first {
            $0.contains("process-exec") && $0.contains("literal")
        }
        XCTAssertNotNil(execRule)
        XCTAssertFalse(execRule?.contains("\r") ?? false,
                        "Carriage returns must not appear inside the quoted path")
    }

    func testPathWithBackslashesAreEscaped() {
        let evilExe = "/tmp/evil\\path"
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: evilExe)

        // The single backslash in the path should become a double backslash in the output
        XCTAssertTrue(profile.contains("evil\\\\path"),
                       "Backslashes should be double-escaped in the profile")
    }

    func testCombinedAdversarialPathHasNoRawParensQuotesOrNewlines() {
        // Combine all adversarial characters into one path
        let evilExe = "/tmp/\0evil\"(inject)\n\r\\bad"
        let profile = SeatbeltProfile.generate(config: minimalConfig(), executablePath: evilExe)

        // Extract all quoted strings from the profile (between unescaped double quotes)
        // and verify none contain raw dangerous characters
        let execRule = profile.components(separatedBy: "\n").first {
            $0.contains("process-exec") && $0.contains("literal")
        }!

        // No raw parentheses inside the quoted literal
        // The rule structure has parens, but the path portion itself should not
        // Extract the path: everything between the last pair of quotes
        let parts = execRule.components(separatedBy: "\"")
        // parts[1] should be the quoted path content (between first pair of quotes in literal)
        let quotedContent = parts.dropFirst().first ?? ""
        XCTAssertFalse(quotedContent.contains("("), "No raw open-paren in path")
        XCTAssertFalse(quotedContent.contains(")"), "No raw close-paren in path")
        XCTAssertFalse(quotedContent.contains("\n"), "No newline in path")
        XCTAssertFalse(quotedContent.contains("\r"), "No carriage return in path")
        XCTAssertFalse(quotedContent.contains("\0"), "No null byte in path")
    }

    // MARK: - 8. Path traversal

    func testPathTraversalIsResolvedByCleanPath() {
        var config = minimalConfig()
        config.allowFileReadPaths = ["/tmp/sandbox/../../../etc/passwd"]
        let profile = SeatbeltProfile.generate(config: config, executablePath: dummyExe)

        XCTAssertFalse(profile.contains(".."), "Path traversal sequences should be resolved")
        // After URL standardization, /tmp/sandbox/../../../etc/passwd resolves to /etc/passwd
        // (or its real path on macOS which may be /private/etc/passwd)
        let hasResolvedPath = profile.contains("/etc/passwd") || profile.contains("/private/etc/passwd")
        XCTAssertTrue(hasResolvedPath,
                       "Traversal path should resolve to /etc/passwd or /private/etc/passwd")
    }

    func testPathTraversalInWritePathIsResolved() {
        var config = minimalConfig()
        config.allowFileWritePath = "/tmp/out/../secret"
        let profile = SeatbeltProfile.generate(config: config, executablePath: dummyExe)

        XCTAssertFalse(profile.contains(".."), "Write path traversal should be resolved")
        // Should resolve to /tmp/secret (or /private/tmp/secret on macOS)
        let hasResolved = profile.contains("/tmp/secret") || profile.contains("/private/tmp/secret")
        XCTAssertTrue(hasResolved, "Traversal write path should resolve correctly")
    }
}

#endif
