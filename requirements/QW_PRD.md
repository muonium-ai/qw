# QW — Product Requirements Document (PRD)
*A Lightweight, Multi-Tab Native macOS Text Editor*

---

## 1. Product Overview

**Product Name:** QW  
**Platform:** macOS (Native)  
**Category:** Text Editor / Developer Utility / Writing Tool

**QW** is a fast, native macOS text editor designed for users who live in text: developers, writers, note-takers, and AI prompt engineers.  
It focuses on speed, clarity, and flow, offering multi-tab editing, syntax highlighting, and minimal distractions — without becoming a heavy IDE.

> **Philosophy:**  
> *Open instantly. Write immediately. Never break flow.*

---

## 2. Goals & Objectives

### Primary Goals
- Ultra-fast launch and typing performance
- True native macOS experience
- Seamless multi-tab workflow
- Clean, readable syntax highlighting

### Non-Goals
- Not an IDE (no debugging, compiling, or project indexing)
- No cloud lock-in in v1
- No account system

---

## 3. Target Users

### Primary Users
- Software developers
- AI practitioners
- Writers & bloggers
- Students and researchers

### Secondary Users
- DevOps engineers
- Product managers

---

## 4. Core Features (MVP)

### 4.1 Multi-Tab Editing
- Open multiple documents in tabs
- Drag to reorder tabs
- Close, duplicate, and pin tabs
- Restore last session on relaunch

**Keyboard Shortcuts**
- Cmd + T — New Tab  
- Cmd + W — Close Tab  
- Cmd + Shift + T — Reopen Closed Tab  
- Cmd + Option + ← / → — Switch Tabs  

---

### 4.2 Syntax Highlighting

Supported formats:
- Plain Text
- Markdown
- JSON
- YAML
- Python
- JavaScript
- HTML / CSS

Features:
- Theme-aware highlighting
- Automatic language detection
- Manual override per tab

---

### 4.3 Native Performance
- Instant startup (< 300 ms target)
- Smooth scrolling for large files
- No UI lag on typing
- Handles files up to ~10 MB

---

### 4.4 Clean Writing Experience
- Line numbers (toggle)
- Word wrap (toggle)
- Minimap (optional)
- Invisible characters toggle
- Find / Replace (regex optional)

---

### 4.5 File Handling
- Open, edit, save local files
- Autosave support
- Unsaved changes indicator
- External file change detection

---

### 4.6 Hex Editor

View and edit binary files with a dedicated hex editing mode.

#### Hex Viewing
- Display file contents in canonical hex dump format: offset | hex bytes | ASCII
- 16 bytes per row with configurable grouping (1, 2, 4, 8 bytes)
- Offset gutter (hex address column)
- ASCII sidebar showing printable characters (non-printable shown as `.`)
- Alternating row backgrounds for readability
- Syntax coloring by byte value (null bytes, printable ASCII, high bytes)
- File size display and current cursor offset in status bar

#### Hex Editing
- Click to select a byte in hex or ASCII pane
- Type hex digits to overwrite bytes in hex pane
- Type characters to overwrite bytes in ASCII pane
- Insert and delete bytes (with confirmation for size-changing edits)
- Undo/redo support
- Find & replace in hex (search by hex pattern or ASCII string)
- Go-to-offset (decimal or hex)

#### Mode Switching
- Auto-detect binary files on open (presence of null bytes or non-UTF-8 sequences)
- Manual toggle between text mode and hex mode via menu/shortcut (Cmd+Shift+H)
- Prompt user when opening a binary file: "This file appears to be binary. Open in hex mode?"
- Hex mode available for any file regardless of content

#### Performance
- Lazy loading / virtual scrolling for large binary files (up to 100 MB)
- Memory-mapped I/O for files > 10 MB
- Edits stored as a patch list — no full file copy in memory

#### Export
- Copy selection as hex string, C array, Swift byte array, or raw bytes
- Export visible range or full file as hex dump text

---

## 5. macOS-Native UX Principles
- AppKit / SwiftUI hybrid
- Native menu bar integration
- Trackpad gestures
- Full keyboard navigation

---

## 6. Settings & Preferences

### Appearance
- Light / Dark / System theme
- Font family & size
- Tab width
- Line height

### Editor Behavior
- Auto-indent
- Smart quotes toggle
- Trailing whitespace trim
- Default file type for new tabs

---

## 7. Technical Architecture

- **Language:** Swift  
- **UI:** SwiftUI + AppKit  
- **Text Engine:** TextKit 2  
- **Highlighting:** Custom tokenizer (MVP), Tree-sitter (future)

---

## 8. Performance Targets

| Metric | Target |
|------|-------|
| Launch time | < 300 ms |
| Typing latency | < 16 ms |
| File open (1MB) | < 100 ms |
| Memory usage | < 150 MB |

---

## 9. Accessibility
- VoiceOver support
- High contrast compatibility
- Keyboard-only navigation
- Scalable fonts

---

## 10. Security & Privacy
- Local-only files
- No telemetry by default
- Sandboxed macOS app

---

## 11. Future Enhancements

### Phase 2
- Hex editor (view & edit binary files)
- Split view
- Markdown preview
- Command palette
- Recent file switcher

### Phase 3
- AI-assisted writing
- Plugin system
- Git diff viewer
- Spotlight integration

---

## 12. Monetization (Optional)
- Free core editor
- One-time purchase for Pro features

---

## 13. Success Metrics
- Time-to-first-keystroke
- Daily active usage
- Retention (7 / 30 days)

---

## 14. One-Line Pitch

**QW** is a fast, native macOS text editor that stays out of your way — so your thoughts can move at typing speed.
