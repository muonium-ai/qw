# Code Review: qw - Native macOS Text Editor

**Date:** 2026-03-25
**Reviewer:** Claude Opus 4.6
**Scope:** Full codebase review

---

## Overall Assessment

Well-structured Swift/SwiftUI app with clean separation of concerns. The code is readable, consistent, and the architecture is sound. Below are the issues found, organized by severity.

---

## Bugs

### 1. Export uses hardcoded light theme (T-000004)

In `DocumentEditorView.swift:196`, `line 210`, and `line 226`, all three export functions hardcode `.light`:

```swift
theme: settings.syntaxTheme(for: .light), // Use light theme for printing
```

The `DocumentExporter` already has a convenience init that takes `colorScheme`, but it's never used from these call sites. The fix is to pass the actual `colorScheme` from the environment (printing could arguably stay light, but PDF/PNG should respect the user's theme).

### 2. `readableContentTypes` returns `[.item]` but tests assert specific types

`TextDocument.swift:53` returns `[.item]` (accepts everything), but `TextDocumentTests.swift:100-108` asserts it contains `.plainText`, `.json`, etc. These tests pass only because `.item` is a supertype, but the intent is misleading — the document claims to read *all* file types, not just the listed ones.

### 3. Cursor position calculation uses `String.Index` as character offset (T-000012)

`CodeEditorView.swift:623` iterates with `enumerated()` which gives UTF-8 character indices, but `selectedRange.location` is a UTF-16 offset (NSRange). For text with emoji or non-BMP characters, the cursor position will be wrong.

---

## Design Issues

### 4. `SyntaxHighlighter` re-created on every keystroke (T-000013)

In `CodeEditorView.swift:666`, a new `SyntaxHighlighter` (and underlying `Lexer`) is allocated on every `textDidChange`. Since the file type and theme rarely change, caching the highlighter in the Coordinator would reduce allocation churn.

### 5. Line-by-line tokenization in export vs full-text tokenization (T-000014)

`DocumentExporter.swift:112-131` uses full-text tokenization when `includeLineNumbers` is false, but falls back to per-line tokenization (line 146) when line numbers are on. Per-line tokenization breaks multi-line constructs (multi-line strings, block comments). The full-text approach should be used in both paths.

### 6. `paragraphStyle.copy()` called for every token

In `DocumentExporter.swift:140` and surrounding lines, `paragraphStyle.copy()` is called per-token and per-line-number. Since the style is identical for all tokens, a single immutable copy would suffice.

### 7. `EditorSettingsManager.shared` singleton accessed from views directly

Multiple views create their own `@ObservedObject private var settings = EditorSettingsManager.shared`. This works but is fragile — if `EditorSettingsManager` were ever recreated, the `@ObservedObject` wrappers wouldn't track the new instance. Using `@EnvironmentObject` would be more idiomatic SwiftUI.

---

## Minor Issues

### 8. `QWDocumentScene` is unused (T-000015)

`DocumentEditorView.swift:306-318` defines `QWDocumentScene` which duplicates the scene in `qwApp.swift` but without read-only mode or menu commands. It appears to be dead code.

### 9. `ContentView.swift` and `Item.swift` are likely Xcode template leftovers (T-000015)

These are the default SwiftData files from Xcode's project template and don't appear to be used by the actual app.

### 10. Search match highlighting not visible in the editor (T-000016)

`SearchState` tracks matches and current match index, but neither `CodeEditorView` nor the `MacOSTextEditor` Coordinator receives or renders match highlighting in the text view. The search bar shows "1/5" but the user can't see *where* the match is.

### 11. `SearchReplaceView.updateMatchInfo` is never called (T-000017)

`SearchReplaceView.swift:123-126` defines `updateMatchInfo(current:total:)` to set `@State` properties `matchCount` and `currentMatch`, but nothing calls it — so the match count display always shows "0/0".

### 12. `readableContentTypes` is too broad (T-000018)

Using `[.item]` means macOS will offer qw as an opener for *any* file type (images, binaries, etc.), which will confuse users since the app can only handle UTF-8 text.

### 13. No `Equatable` conformance on `SyntaxTheme`

Theme change detection in `updateNSView` relies on comparing `themeName` strings rather than the theme struct itself. If the theme were `Equatable`, change detection would be more robust.

---

## What's Done Well

- Clean modular architecture: Models / Views / Editor / Export separation
- Canvas-based line numbers view — efficient for large files
- Proper `beginEditing/endEditing` batching for syntax highlighting
- 100KB safety limit for syntax highlighting prevents UI hangs
- Good use of `NSViewRepresentable` with proper Coordinator pattern
- Thoughtful read-only mode with CLI integration
- Multiple layout passes in `CodeRender` to handle width estimation correctly

---

## Priority Recommendations

| Priority | Issue | Ticket | Effort |
|----------|-------|--------|--------|
| P1 | Fix export theme | T-000004 | XS |
| P1 | Fix cursor position UTF-16 mismatch | T-000012 | S |
| P2 | Fix search match display (not visible) | T-000016 | M |
| P2 | Fix search match counter always 0/0 | T-000017 | XS |
| P2 | Use full-text tokenization for export with line numbers | T-000014 | S |
| P2 | Narrow readableContentTypes | T-000018 | S |
| P3 | Cache SyntaxHighlighter in Coordinator | T-000013 | XS |
| P3 | Remove dead code (QWDocumentScene, ContentView, Item) | T-000015 | XS |
