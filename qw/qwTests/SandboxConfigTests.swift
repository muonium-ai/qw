//
//  SandboxConfigTests.swift
//  qwTests
//
//  Tests for SandboxConfig default values, presets, and security invariants.
//

#if os(macOS)
import XCTest
@testable import qw

final class SandboxConfigTests: XCTestCase {

    // MARK: - Default values

    func testDefaultValues() {
        let config = SandboxConfig()

        XCTAssertFalse(config.allowNetwork)
        XCTAssertEqual(config.allowFileReadPaths, [])
        XCTAssertNil(config.allowFileWritePath)
        XCTAssertFalse(config.allowProcessSpawn)
        XCTAssertEqual(config.memoryLimitMB, 256)
        XCTAssertEqual(config.cpuTimeoutSeconds, 30)
        XCTAssertEqual(config.maxOutputBytes, 1_048_576)
        XCTAssertEqual(config.environment, [:])
    }

    // MARK: - wasmDefault preset

    func testWasmDefaultNoNetworkNoSpawn() {
        let config = SandboxConfig.wasmDefault

        XCTAssertFalse(config.allowNetwork)
        XCTAssertFalse(config.allowProcessSpawn)
    }

    func testWasmDefaultNoFilePaths() {
        let config = SandboxConfig.wasmDefault

        XCTAssertTrue(config.allowFileReadPaths.isEmpty)
        XCTAssertNil(config.allowFileWritePath)
    }

    func testWasmDefaultResourceLimits() {
        let config = SandboxConfig.wasmDefault

        XCTAssertEqual(config.memoryLimitMB, 256)
        XCTAssertEqual(config.cpuTimeoutSeconds, 30)
        XCTAssertEqual(config.maxOutputBytes, 1_048_576)
    }

    func testWasmDefaultEmptyEnvironment() {
        let config = SandboxConfig.wasmDefault

        XCTAssertTrue(config.environment.isEmpty)
    }

    // MARK: - nativeDefault preset

    func testNativeDefaultReadPaths() {
        let exe = "/usr/local/bin/myapp"
        let tmp = "/tmp/sandbox-abc"
        let config = SandboxConfig.nativeDefault(executablePath: exe, tmpDir: tmp)

        XCTAssertTrue(config.allowFileReadPaths.contains(exe))
    }

    func testNativeDefaultWritePath() {
        let exe = "/usr/local/bin/myapp"
        let tmp = "/tmp/sandbox-abc"
        let config = SandboxConfig.nativeDefault(executablePath: exe, tmpDir: tmp)

        XCTAssertEqual(config.allowFileWritePath, tmp)
    }

    func testNativeDefaultMemoryHigherThanDefault() {
        let config = SandboxConfig.nativeDefault(executablePath: "/bin/ls", tmpDir: "/tmp")

        XCTAssertEqual(config.memoryLimitMB, 512)
        XCTAssertGreaterThan(config.memoryLimitMB, SandboxConfig().memoryLimitMB)
    }

    func testNativeDefaultNoNetworkNoSpawn() {
        let config = SandboxConfig.nativeDefault(executablePath: "/bin/ls", tmpDir: "/tmp")

        XCTAssertFalse(config.allowNetwork)
        XCTAssertFalse(config.allowProcessSpawn)
    }

    // MARK: - wineDefault preset

    func testWineDefaultReadPaths() {
        let exe = "/home/user/game.exe"
        let prefix = "/home/user/.wine"
        let config = SandboxConfig.wineDefault(executablePath: exe, winePrefix: prefix)

        XCTAssertTrue(config.allowFileReadPaths.contains(exe))
        XCTAssertTrue(config.allowFileReadPaths.contains(prefix))
    }

    func testWineDefaultWritePath() {
        let prefix = "/home/user/.wine"
        let config = SandboxConfig.wineDefault(executablePath: "/home/user/game.exe", winePrefix: prefix)

        XCTAssertEqual(config.allowFileWritePath, prefix)
    }

    func testWineDefaultLongerTimeout() {
        let config = SandboxConfig.wineDefault(executablePath: "/game.exe", winePrefix: "/wine")

        XCTAssertEqual(config.cpuTimeoutSeconds, 60)
        XCTAssertGreaterThan(config.cpuTimeoutSeconds, SandboxConfig().cpuTimeoutSeconds)
    }

    func testWineDefaultEnvironment() {
        let prefix = "/home/user/.wine"
        let config = SandboxConfig.wineDefault(executablePath: "/game.exe", winePrefix: prefix)

        XCTAssertEqual(config.environment["WINEPREFIX"], prefix)
    }

    // MARK: - jvmDefault preset

    func testJvmDefaultReadPaths() {
        let jar = "/opt/app/server.jar"
        let tmp = "/tmp/jvm-sandbox"
        let config = SandboxConfig.jvmDefault(jarPath: jar, tmpDir: tmp)

        XCTAssertTrue(config.allowFileReadPaths.contains(jar))
    }

    func testJvmDefaultWritePath() {
        let tmp = "/tmp/jvm-sandbox"
        let config = SandboxConfig.jvmDefault(jarPath: "/app.jar", tmpDir: tmp)

        XCTAssertEqual(config.allowFileWritePath, tmp)
    }

    func testJvmDefaultMemory() {
        let config = SandboxConfig.jvmDefault(jarPath: "/app.jar", tmpDir: "/tmp")

        XCTAssertEqual(config.memoryLimitMB, 256)
    }

    // MARK: - Security invariants across all presets

    func testNoPresetEnablesNetwork() {
        let presets: [SandboxConfig] = [
            .wasmDefault,
            .nativeDefault(executablePath: "/bin/x", tmpDir: "/tmp"),
            .wineDefault(executablePath: "/x.exe", winePrefix: "/wine"),
            .jvmDefault(jarPath: "/x.jar", tmpDir: "/tmp"),
        ]

        for (index, config) in presets.enumerated() {
            XCTAssertFalse(config.allowNetwork, "Preset at index \(index) should not allow network")
        }
    }

    func testNoPresetEnablesProcessSpawn() {
        let presets: [SandboxConfig] = [
            .wasmDefault,
            .nativeDefault(executablePath: "/bin/x", tmpDir: "/tmp"),
            .wineDefault(executablePath: "/x.exe", winePrefix: "/wine"),
            .jvmDefault(jarPath: "/x.jar", tmpDir: "/tmp"),
        ]

        for (index, config) in presets.enumerated() {
            XCTAssertFalse(config.allowProcessSpawn, "Preset at index \(index) should not allow spawn")
        }
    }

    func testAllPresetsCapOutputAtOneMB() {
        let presets: [SandboxConfig] = [
            .wasmDefault,
            .nativeDefault(executablePath: "/bin/x", tmpDir: "/tmp"),
            .wineDefault(executablePath: "/x.exe", winePrefix: "/wine"),
            .jvmDefault(jarPath: "/x.jar", tmpDir: "/tmp"),
        ]

        for (index, config) in presets.enumerated() {
            XCTAssertEqual(config.maxOutputBytes, 1_048_576,
                           "Preset at index \(index) should cap output at 1 MB")
        }
    }
}
#endif
