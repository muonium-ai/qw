# QW Editor Security Model

## Threat Model

A malicious file should never execute code by being opened in QW.

QW is a plain-text editor and hex viewer. It does not interpret or execute
file contents in any way beyond rendering text and applying syntax highlighting
via regex-based tokenization.

## Attack Surfaces Audited

### Text Editor (Swift/SwiftUI)
- File contents are loaded as plain `String` via `String(contentsOf:encoding:.utf8)`.
- No `NSAppleScript`, `Process`, `NSTask`, `JSContext`, `NSExpression`,
  `WKWebView`, `evaluateJavaScript`, `eval`, `exec`, `system()`, or `popen`
  calls exist anywhere in the codebase.
- `NSAttributedString` is constructed only from literal font/color attributes
  for syntax-highlighted export (PDF/PNG). No HTML or RTF document-type
  initializers are used, so no external resource loading can be triggered.

### Syntax Highlighter
- Uses regex-based tokenization (`SyntaxHighlighter.tokenize`).
- Output is purely cosmetic (foreground color attributes). No code evaluation.

### Export (PDF / PNG / Print)
- Renders `NSAttributedString` with font and color attributes into
  `NSTextView` for layout, then captures via Core Graphics.
- No shell-outs or script execution.

### Hex View
- Displays raw bytes. No interpretation or execution of binary content.

### Filenames
- Filenames are used for display and file-type detection only.
- No filename is interpolated into shell commands or evaluated.

### CLI Script (`cli/qw`)
- All variable expansions are properly quoted.
- Command arguments to `enscript` are passed via bash arrays to prevent
  word-splitting injection.
- Temporary files use `mktemp` with random suffixes to prevent symlink attacks
  (TOCTOU races on predictable `/tmp` paths).
- The `ext` variable (derived from filename) is only matched against a fixed
  set of known literals in a `case` statement; unrecognized extensions are
  ignored.

## App Sandbox

The macOS app is sandboxed (`com.apple.security.app-sandbox = true` in
`qw.entitlements`). Entitlements granted:

| Entitlement | Purpose |
|---|---|
| `files.user-selected.read-write` | Read/write files the user explicitly opens |
| `files.bookmarks.app-scope` | Persist access to previously-opened files |
| `icloud-container-identifiers` | iCloud document sync |

No network, scripting, or process-execution entitlements are granted.

## Guarantees

1. Opening any file (text or binary) in QW will never execute code from that file.
2. Syntax highlighting is purely cosmetic and regex-based.
3. Export to PDF/PNG does not interpret file contents as markup.
4. The CLI wrapper does not pass file contents or names into shell evaluation.
5. The app sandbox restricts filesystem and network access at the OS level.
