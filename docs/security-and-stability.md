# QW Editor — Security & Stability Reference

This document catalogues all known security considerations, past crashes, and
defensive measures in the qw codebase. It serves as a reference for code review,
threat modelling, and future hardening work.

---

## 1. Crash History

### 1.1 AttributeGraph Exhaustion (T-000061)

- **Symptom:** `AG::precondition_failure` → `SIGABRT` on main thread when opening
  large files in hex view.
- **Root cause:** `HexView` created 32+ individual `Text` subviews per row, each
  with 2 gesture modifiers (tap + shift-tap). For a 1 MB file (65,536 rows) this
  produced ~2 million gesture-modified views, exhausting SwiftUI's AttributeGraph.
- **Stack signature:** `AG::data::table::grow_region` → `AG::precondition_failure`,
  deep recursion through `ModifiedElements.makeElements` (11 levels).
- **Fix:** Replaced per-byte `ForEach` with `AttributedString`-based rendering.
  Row view count dropped from ~35 to ~8; gesture registrations from ~64 to ~6.
- **Lesson:** Never use `ForEach` with per-element gesture modifiers inside
  `LazyVStack` for large collections. Prefer `AttributedString` for styled text
  with single gestures and position-based hit testing.

### 1.2 Infinite "Probing Media" Spinner (T-000062)

- **Symptom:** Clicking the film/media toolbar button on a non-media file (e.g.
  SQLite) showed `MediaMetadataPanel` stuck on "Probing media..." forever.
- **Root cause:** The toolbar button was visible for all file types. Clicking it
  set `showMediaMetadata = true`, then called `triggerFFprobeIfNeeded()` which
  returned early (not a media file), leaving `ffprobeResult` as nil. The panel
  shows a spinner when result is nil.
- **Fix:** Added `isMediaFile` computed property; button only renders when the
  file is detected as audio/video.
- **Lesson:** Toolbar buttons that trigger async work must guard visibility on
  the same predicate the async work uses, or handle the "nothing to do" state.

---

## 2. Security Architecture

### 2.1 File Type Detection — Magic Bytes, Not Extensions

QW identifies file types by reading binary content (magic bytes), not by trusting
file extensions. This is critical because:

- Downloaded files may have wrong extensions (innocent or malicious).
- A file named `resume.pdf` could contain a Mach-O executable.
- Extension-based routing would open it in the wrong viewer.

**Current implementation:**
- `MagicBytes.detect(from: Data)` — hardcoded signature registry
- `FormatDatabase.shared.detectSignature(from: Data)` — SQLite-backed, 44 signatures
- Both are used for auto-routing to image/video/audio/hex modes

**Gap:** No mismatch detection between extension and detected content. A disguised
executable could be auto-routed to a media player (which would fail gracefully) but
the user is not warned about the mismatch.

### 2.2 Sandbox Execution Framework

The app can execute binary files in a restricted sandbox. The security model is
defence-in-depth:

| Layer | Mechanism | What it restricts |
|-------|-----------|-------------------|
| **OS sandbox** | `sandbox-exec` seatbelt profile | Filesystem, network, IPC, devices |
| **Resource limits** | RLIMIT_CPU, RLIMIT_AS, timeout watchdog | CPU time, memory |
| **Runtime sandbox** | WASI (WASM), Java SecurityManager | Runtime-level capabilities |
| **Environment** | Sanitised env vars, disposable tmpdir | Credential leakage, persistence |
| **UI consent** | `ExecutionConfirmDialog` | User must approve before any execution |

#### 2.2.1 Seatbelt Profile Generation (`SeatbeltProfile.swift`)

- Base policy: `(deny default)` — everything denied unless explicitly allowed.
- Path escaping: null bytes, backslashes, quotes, parentheses, newlines stripped
  to prevent S-expression injection in seatbelt profiles.
- Paths normalised via `URL.standardized` to prevent `../` traversal.

**Risk:** Seatbelt profiles are string-based. Any future changes to path escaping
must be reviewed for injection. Consider fuzzing the escaping function.

#### 2.2.2 Runner-Specific Security

| Runner | Key risk | Mitigation |
|--------|----------|------------|
| **WASM** (wasmtime/wasmer) | Inherently sandboxed; low risk | No WASI capabilities granted by default |
| **Native** (Mach-O/ELF) | Full native code execution | Strict seatbelt, RLIMIT, kill on timeout |
| **Wine** (PE/EXE) | Wine translates Win32 API to host | Disposable WINEPREFIX, seatbelt wrapping |
| **JVM** (JAR) | Java can reflect/load classes | SecurityManager + seatbelt double layer |

#### 2.2.3 Environment Sanitisation (`SandboxEnvironment.swift`)

Stripped from child process environment:
- `HOME`, `USER`, `LOGNAME` — identity
- `SSH_AUTH_SOCK`, `SSH_AGENT_PID` — SSH keys
- `AWS_*`, `GITHUB_TOKEN`, `ANTHROPIC_API_KEY` — credentials
- `HISTFILE`, `SHELL` — shell context

Only allowed: `PATH` (minimal), `TMPDIR`, `LANG`.

### 2.3 Process Execution Inventory

The app now executes external processes in these contexts:

| Context | Binary | File | Risk level |
|---------|--------|------|------------|
| Quick Look preview | `/usr/bin/qlmanage -p` | `DocumentEditorView.swift` | Low — system binary, read-only |
| Open in Default App | `NSWorkspace.shared.open()` | Multiple views | Low — OS-managed |
| ffprobe metadata | `ffprobe` | `FFprobeService.swift` | Low — read-only, no sandbox needed |
| WASM execution | `wasmtime`/`wasmer` | `WasmRunner.swift` | Medium — WASI-sandboxed |
| Native execution | Direct / `qemu-user` | `NativeRunner.swift` | **High** — seatbelt required |
| Wine execution | `wine` | `WineRunner.swift` | **High** — seatbelt + disposable prefix |
| JVM execution | `java -jar` | `JvmRunner.swift` | **High** — SecurityManager + seatbelt |

### 2.4 App Sandbox Entitlements

The macOS app sandbox (`com.apple.security.app-sandbox = true`) grants:

| Entitlement | Purpose |
|---|---|
| `files.user-selected.read-write` | Read/write files the user explicitly opens |
| `files.bookmarks.app-scope` | Persist access to previously-opened files |
| `icloud-container-identifiers` | iCloud document sync |

**Note:** Process execution from a sandboxed app may require additional
entitlements or may need to be performed via XPC services. The sandbox runners
currently assume the app can invoke `Process` — this needs validation when
distributing via the App Store.

### 2.5 Logging (`FormatLogger.swift`)

All file open attempts are logged via `os.Logger(subsystem: "com.muonium.qw",
category: "formats")`:

- **Success:** file extension, detected format name, mode (image/video/audio/hex/text)
- **Failure:** same fields + error description

Logs are visible in Console.app and can be used to identify unsupported formats
and potential misuse patterns.

---

## 3. Known Gaps & Future Work

### 3.1 Extension vs Content Mismatch Detection (Not Yet Implemented)

**Threat:** A file with a misleading extension (e.g. `photo.jpg` containing a
Mach-O binary) is currently auto-routed based on magic bytes (correct behavior)
but the user is not warned about the mismatch.

**Recommended fix:**
- Compare file extension against detected magic bytes category.
- Severity levels:
  - **Critical:** Extension says document/media, content is executable.
  - **Warning:** Extension and content are both non-executable but don't match.
  - **Info:** No extension or unknown extension.
- Show a prominent warning banner for critical mismatches.
- Block auto-execution for mismatched files.
- Log all mismatches.

### 3.2 Seatbelt Profile Fuzzing

The path escaping in `SeatbeltProfile.swift` should be fuzz-tested to ensure no
injection vectors remain in the S-expression generation.

### 3.3 App Store Sandbox Compatibility

The `Process` invocations (ffprobe, sandbox runners) may not work under App Store
sandbox restrictions. Evaluate whether XPC services are needed for:
- ffprobe invocation
- Sandbox execution runners

### 3.4 Large File Handling

While the AttributeGraph crash is fixed for hex view, other views should be
audited for similar patterns:
- `AnnotationPanelView` uses `ForEach` with `enumerated()` — currently small
  datasets but could grow.
- `HexDiffView` uses `ForEach(0..<rowCount)` with nested per-byte `ForEach` —
  same pattern as the original crash.

### 3.5 Media Player Error Handling

- AVPlayer/AVFoundation may hang on certain malformed media files.
- ffprobe has a 5-second timeout but could be tightened.
- Video/audio players now offer "Open in Default App" fallback (T-000053).

---

## 4. Security Checklist for Code Review

When reviewing PRs that touch file handling or execution:

- [ ] Does it use magic bytes (not extensions) for format decisions?
- [ ] Are file paths properly escaped in any string interpolation?
- [ ] Does any new `Process` invocation go through `SandboxExecutor`?
- [ ] Are timeout and resource limits set for any new async operations?
- [ ] Is user consent required before executing any file content?
- [ ] Are environment variables sanitised for child processes?
- [ ] Is the seatbelt profile deny-by-default?
- [ ] Are temporary directories cleaned up in `defer` blocks?
- [ ] Is `FormatLogger` called on both success and failure paths?
- [ ] Could this crash on large inputs? (Check `ForEach` + gesture patterns)
