# PygmentsSwift Upgrade Process (Learnings)

## Scope
This document captures the migration of QW’s syntax highlighting and export pipeline to PygmentsSwift, along with the key learnings and the features replaced by Pygments-backed components.

> Note: The working tree is currently clean, so there are no local git diffs to attach here. The summary below is based on the implementation steps completed in this workspace.

---

## What We Replaced With PygmentsSwift Components

### 1) Syntax Highlighting Tokenization
**Replaced:**
- Custom, regex-based tokenizers for each language (Python/JS/Swift/HTML/CSS/JSON/YAML/Markdown).

**With:**
- PygmentsSwift lexer selection using filename/extension or language name.
- Token mapping from Pygments token types into QW’s `TokenType`.

**Why:**
- Broader language coverage (e.g., PHP, Java, etc.) without writing per-language regex.
- Fewer edge-case errors (e.g., overlapping tokens inside comments).

---

### 2) Export Rendering (PNG/PDF)
**Replaced:**
- Custom PDF/PNG export rendering pipeline that had orientation/inversion issues and incorrect line order.

**With:**
- PygmentsSwift’s codeviewer rendering approach (adopted as `CodeRender` in QW) using `NSTextView` layout.

**Why:**
- Correct line order and text orientation.
- More robust layout for PNG/PDF export.

---

### 3) CLI Export Defaults (qw-export)
**Replaced:**
- Hardcoded CLI defaults (theme, font, font size, line numbers).

**With:**
- CLI now reads QW app defaults via `UserDefaults` (same keys as the app):
  - `editorTheme`
  - `editorFontName`
  - `editorFontSize`
  - `showLineNumbers`

**Why:**
- CLI output now matches the app’s current visual configuration.

---

## Learnings and Notes

### A) Lexer Selection Should Prefer Filename
- PygmentsSwift’s lexer registry is best used by providing the **filename with extension**.
- This enables support for additional file types without updating QW’s internal `SupportedFileType` list.

### B) Token Mapping Strategy
- Pygments categories map cleanly into QW’s UI styling buckets:
  - `comment → .comment`
  - `string → .string`
  - `number → .number`
  - `keyword → .keyword`
  - `name.Function → .function`
  - `name.Class` / `keyword.Type → .type`
  - `name.* → .property`
  - `punctuation / operator → .punctuation`
- This preserves the QW theme palette while expanding language coverage.

### C) Full-Text Tokenization Is Best for Exports
- For export output, highlight the **full document** rather than per-line to avoid token splits and to align with Pygments token ranges.

### D) Rendering Stability
- `NSTextView` layout used by `CodeRender` provides stable sizing and prevents PNG inversion or line-order reversals.

### E) Clean Separation of Responsibilities
- QW continues to own theme colors and layout settings.
- PygmentsSwift owns tokenization and language support.

---

## Summary
The migration replaced QW’s manual tokenization and export rendering with PygmentsSwift-based lexing and rendering, while keeping the app’s theming and editor layout intact. The CLI now mirrors the app’s settings and theme choices for consistent exports.
