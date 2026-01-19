# QW Release Planning

Date: 2026-01-19

## Known Issues to Address Before Public Release

### 1) Word wrap / horizontal scrolling not updating
- **Severity:** High
- **Impact:** Users can’t scroll horizontally when word wrap is off, and toggling wrap may not update the editor UI.
- **Observed in:** [qw/qw/Editor/CodeEditorView.swift](qw/qw/Editor/CodeEditorView.swift#L357-L469)
- **Notes:** `hasHorizontalScroller` is set based on `wordWrap` then forced to `false`. `wordWrap` changes are not re-applied in `updateNSView`.
- **Proposed fix:** Remove the unconditional `hasHorizontalScroller = false`, and update `textContainer?.widthTracksTextView`, `isHorizontallyResizable`, and `hasHorizontalScroller` inside `updateNSView` when `wordWrap` changes.

### 2) PNG export potential crash (force unwrap)
- **Severity:** High
- **Impact:** App can crash on memory pressure or very large content.
- **Observed in:** [qw/qw/Export/DocumentExporter.swift](qw/qw/Export/DocumentExporter.swift#L404-L418)
- **Notes:** `NSBitmapImageRep(...)!` can return nil.
- **Proposed fix:** Replace force unwrap with guard and surface `ExportError.pngCreationFailed`.

### 3) UTF-8 only read + force unwrap on write
- **Severity:** Medium
- **Impact:** Non‑UTF‑8 files fail to open; potential crash on save (unlikely, but avoid `!`).
- **Observed in:** [qw/qw/Models/TextDocument.swift](qw/qw/Models/TextDocument.swift#L72-L104)
- **Notes:** Read path throws `fileReadCorruptFile` for non‑UTF‑8; write path uses `text.data(using: .utf8)!`.
- **Proposed fix:** Support additional encodings (e.g. UTF‑16) or surface a clearer user error; replace force unwrap with a guard and throw a `CocoaError(.fileWriteUnknown)` or custom error.

### 4) PDF pagination fixed at 28 lines
- **Severity:** Medium
- **Impact:** PDF export can cut off lines or leave excessive whitespace when font size/line height changes.
- **Observed in:** [qw/qw/Export/DocumentExporter.swift](qw/qw/Export/DocumentExporter.swift#L206-L238)
- **Notes:** Uses a fixed `pdfLinesPerPage` and fixed page size rather than computing layout from font/line height.
- **Proposed fix:** Calculate lines per page from `lineHeight` and usable page height, or paginate using `NSLayoutManager`/`NSTextContainer` to avoid clipping.

### 5) Export runs on main thread + verbose logging
- **Severity:** Medium
- **Impact:** UI can freeze for large exports; release builds may log file paths.
- **Observed in:** [qw/qw/Export/DocumentExporter.swift](qw/qw/Export/DocumentExporter.swift#L458-L515)
- **Notes:** Save panel completion runs export on the main thread and prints paths.
- **Proposed fix:** Dispatch export to a background queue and report completion on main; gate logs behind a debug flag or remove for release.

### 6) NotificationCenter observer never removed (potential memory leak)
- **Severity:** Medium
- **Impact:** Coordinator may leak or receive spurious scroll notifications after the view is removed.
- **Observed in:** [qw/qw/Editor/CodeEditorView.swift](qw/qw/Editor/CodeEditorView.swift#L401-L406)
- **Notes:** `NotificationCenter.default.addObserver` is called in `makeNSView`, but there is no `deinit` or `dismantleNSView` to call `removeObserver`.
- **Proposed fix:** Add a `deinit` to the `Coordinator` that calls `NotificationCenter.default.removeObserver(self)`.

### 7) Unused SwiftData boilerplate (ContentView.swift, Item.swift)
- **Severity:** Low
- **Impact:** Code clutter; unused SwiftData model adds to binary size and confusion.
- **Observed in:** [qw/qw/ContentView.swift](qw/qw/ContentView.swift), [qw/qw/Item.swift](qw/qw/Item.swift)
- **Notes:** These files appear to be Xcode template leftovers and are not used by the app.
- **Proposed fix:** Remove `ContentView.swift` and `Item.swift` if they are not needed.

### 8) iCloud entitlements present but no iCloud sync implemented
- **Severity:** Low
- **Impact:** App may prompt user for iCloud access that is never used; may cause App Store review issues.
- **Observed in:** [qw/qw/qw.entitlements](qw/qw/qw.entitlements)
- **Notes:** iCloud container identifiers and CloudDocuments entitlements are declared but unused.
- **Proposed fix:** Remove iCloud entitlements if iCloud sync is not planned for v1; or implement iCloud document sync.

### 9) Search/Replace does not highlight current match in editor
- **Severity:** Low
- **Impact:** User cannot visually locate the current match in the document; only match count is shown.
- **Observed in:** [qw/qw/Views/SearchReplaceView.swift](qw/qw/Views/SearchReplaceView.swift), [qw/qw/Views/DocumentEditorView.swift](qw/qw/Views/DocumentEditorView.swift)
- **Notes:** `SearchState` tracks `matches` and `currentMatchIndex`, but the editor does not scroll to or highlight the match.
- **Proposed fix:** Scroll the text view to the current match range and apply a highlight (e.g. selection or background color).

### 10) Accessibility labels missing for key elements
- **Severity:** Low
- **Impact:** VoiceOver users may have difficulty understanding controls.
- **Observed in:** Various views
- **Notes:** Only `accessibilityIdentifier` is set (for UI testing); `accessibilityLabel` and `accessibilityHint` are missing on buttons and fields.
- **Proposed fix:** Add `.accessibilityLabel()` and `.accessibilityHint()` to interactive elements.

### 11) iOS build incomplete / iOSTextEditor lacks read-only support
- **Severity:** Low (if macOS-only release)
- **Impact:** iOS version would allow editing even when read-only is intended.
- **Observed in:** [qw/qw/Editor/CodeEditorView.swift](qw/qw/Editor/CodeEditorView.swift#L678-L880)
- **Notes:** `iOSTextEditor` does not accept or enforce `isReadOnly`.
- **Proposed fix:** Add `isReadOnly` parameter to `iOSTextEditor` and disable editing when true.

### 12) App automatically creates untitled document on launch
- **Severity:** Low
- **Impact:** Users may not want an empty document created automatically.
- **Observed in:** [qw/qw/qwApp.swift](qw/qw/qwApp.swift#L72-76)
- **Notes:** `QWAppDelegate.applicationDidFinishLaunching` creates a new document if none are open.
- **Proposed fix:** Remove the automatic document creation or make it optional via settings.

### 13) No version information displayed in app
- **Severity:** Low
- **Impact:** Users cannot check the app version from within the app.
- **Observed in:** No version display in UI.
- **Notes:** App lacks an "About" window or version info in settings.
- **Proposed fix:** Add an "About QW" menu item or settings section showing version from Info.plist.

### 14) CLI export error handling incomplete
- **Severity:** Medium
- **Impact:** CLI exports may fail silently or with unclear errors.
- **Observed in:** [cli/qw](cli/qw), [qw-export/main.swift](qw-export/main.swift)
- **Notes:** CLI scripts use `try` but may not surface errors properly to user.
- **Proposed fix:** Improve error messages and exit codes in CLI tools.

### 15) Syntax highlighter may not handle all edge cases
- **Severity:** Low
- **Impact:** Some code may not highlight correctly.
- **Observed in:** [qw/qw/Editor/SyntaxHighlighter.swift](qw/qw/Editor/SyntaxHighlighter.swift)
- **Notes:** Regex-based highlighting may miss complex syntax or multi-line constructs.
- **Proposed fix:** Test with various code samples and refine regex patterns if needed.

### 16) Large file performance degradation
- **Severity:** Medium
- **Impact:** App may become unresponsive with very large files (>10MB).
- **Observed in:** Syntax highlighting skips large files, but scrolling/rendering may still lag.
- **Notes:** NSTextView handles large files, but highlighting and UI updates may cause issues.
- **Proposed fix:** Add file size warnings or disable features for large files.

### 17) Syntax highlighting overlaps/priority issues
- **Severity:** Low
- **Impact:** Tokens found later (e.g., strings) overwrite earlier ones (e.g., comments) regardless of logic.
- **Observed in:** [qw/qw/Editor/SyntaxHighlighter.swift](qw/qw/Editor/SyntaxHighlighter.swift), [qw-export/Sources/qw-export.swift](qw-export/Sources/qw-export.swift)
- **Notes:** Applying attributes sequentially based on simplistic regex without token merging logic leads to artifacts (e.g., string color inside a comment).
- **Proposed fix:** Implement a scanner/lexer that produces a non-overlapping stream of tokens, or sort and merge ranges carefully.



### 18) Makefile install targets fail on permissions
- **Severity:** Medium
- **Impact:** `make install` fails with "Permission denied".
- **Observed in:** [Makefile](Makefile)
- **Notes:** Writes to `/Applications` and `/usr/local/bin` without sudo handling.
- **Proposed fix:** Add `sudo` to commands or partial error handling; instructions to run with sudo.

### 19) Duplicate syntax/theme code not shared between App and Export tool
- **Severity:** Low (Maintenance)
- **Impact:** Fixes in app (e.g., regex) are not reflected in CLI exporter.
- **Observed in:** [qw-export/Sources/qw-export.swift](qw-export/Sources/qw-export.swift) vs [qw/qw/Editor/SyntaxHighlighter.swift](qw/qw/Editor/SyntaxHighlighter.swift)
- **Notes:** `qw-export` is a standalone script that duplicates the app's logic.
- **Proposed fix:** Extract core logic into a shared Swift package or framework used by both targets.

---

## Pre-Release Checklist

- [ ] Fix critical build settings (Target 26.1 -> 13.0)
- [ ] Fix all **High** severity code issues (#1, #2, #18)
- [ ] Fix Permission/Install issues in Makefile (#19)
- [ ] Implement missing read-only support for iOS (#11)
- [ ] Ensure `App` doesn't leak memory (NotificationCenter #6)
- [ ] Decide on duplicate code strategy (#20)
- [ ] Clean up unused files (#7)
- [ ] Verify entitlements (#8)
- [ ] Regression test all features
- [ ] Create signed Release build
- [ ] Verify CLI tools export correctly
- [ ] Update README and docs


