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
