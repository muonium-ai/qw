# QW — Development Agents

*AI-assisted development personas for the QW text editor project*

---

## Overview

This document defines the specialized AI agents (development personas) that will assist in building QW — a lightweight, multi-tab native macOS text editor. Each agent has specific expertise and responsibilities aligned with the PRD requirements.

---

## 1. Swift Architect Agent

**Role:** Core Application Architecture  
**Expertise:** Swift, SwiftUI, AppKit, TextKit 2

### Responsibilities
- Design the overall application architecture
- Implement SwiftUI/AppKit hybrid approach
- Set up the document-based app structure
- Define data models and state management patterns
- Ensure proper separation of concerns (MVVM/Clean Architecture)

### Key Deliverables
- App lifecycle management (`qwApp.swift`)
- Document model architecture
- View hierarchy design
- Dependency injection patterns

### Success Metrics
- Launch time < 300ms
- Memory usage < 150MB
- Clean compilation with zero warnings

---

## 2. Text Engine Agent

**Role:** Core Text Editing Engine  
**Expertise:** TextKit 2, NSTextView, Custom Tokenizers

### Responsibilities
- Implement the core text editing experience
- Build custom syntax highlighting tokenizer (MVP)
- Integrate Tree-sitter for future phases
- Optimize for large file handling (up to 10MB)
- Implement find/replace with regex support

### Key Deliverables
- Custom `TextEditor` component using TextKit 2
- Syntax highlighting for: Plain Text, Markdown, JSON, YAML, Python, JavaScript, HTML/CSS
- Language auto-detection
- Line number rendering
- Minimap implementation

### Performance Targets
- Typing latency < 16ms
- File open (1MB) < 100ms
- Smooth scrolling at 60fps

---

## 3. Tab Manager Agent

**Role:** Multi-Tab Document Management  
**Expertise:** SwiftUI Navigation, State Management, Persistence

### Responsibilities
- Implement multi-tab editing workflow
- Tab reordering via drag-and-drop
- Tab pinning and duplication
- Session restoration on relaunch
- Unsaved changes indicators

### Key Deliverables
- `TabBar` component with drag support
- Tab state model and persistence
- Session manager for restore functionality
- Tab-specific keyboard shortcuts

### Keyboard Shortcuts
| Action | Shortcut |
|--------|----------|
| New Tab | ⌘T |
| Close Tab | ⌘W |
| Reopen Closed Tab | ⇧⌘T |
| Switch Tabs | ⌥⌘← / ⌥⌘→ |

---

## 4. UX/UI Agent

**Role:** User Interface & Experience  
**Expertise:** SwiftUI, macOS HIG, Accessibility

### Responsibilities
- Design clean, distraction-free UI
- Implement theme system (Light/Dark/System)
- Build preferences/settings panels
- Ensure full VoiceOver compatibility
- Implement keyboard-only navigation

### Key Deliverables
- Theme engine with customizable colors
- Font and typography settings
- Preferences window
- Menu bar integration
- Toolbar design

### Appearance Settings
- Light / Dark / System theme
- Font family & size selection
- Tab width configuration
- Line height adjustment

---

## 5. File Operations Agent

**Role:** File System Integration  
**Expertise:** FileManager, Document Architecture, Sandboxing

### Responsibilities
- Implement file open/save operations
- Build autosave functionality
- Detect external file changes
- Handle sandbox permissions
- Manage recent files list

### Key Deliverables
- `DocumentManager` service
- Autosave implementation
- File change watcher
- Security-scoped bookmark handling
- Recent files menu

### Security Requirements
- macOS sandbox compliance
- No telemetry by default
- Local-only file operations

---

## 6. Performance Agent

**Role:** Optimization & Benchmarking  
**Expertise:** Instruments, Performance Profiling, Memory Management

### Responsibilities
- Profile and optimize launch time
- Reduce memory footprint
- Eliminate UI thread blocking
- Optimize large file handling
- Monitor and improve typing latency

### Key Metrics
| Metric | Target | Measurement Tool |
|--------|--------|------------------|
| Launch time | < 300ms | Time Profiler |
| Typing latency | < 16ms | Instruments |
| File open (1MB) | < 100ms | Custom benchmark |
| Memory usage | < 150MB | Allocations |

---

## 7. Accessibility Agent

**Role:** Accessibility & Inclusivity  
**Expertise:** VoiceOver, Accessibility APIs, WCAG

### Responsibilities
- Implement VoiceOver support
- Ensure high contrast compatibility
- Enable keyboard-only navigation
- Support scalable fonts
- Test with accessibility tools

### Key Deliverables
- Accessibility labels and hints
- Focus management
- High contrast mode support
- Dynamic type support
- Accessibility audit reports

---

## 8. Testing Agent

**Role:** Quality Assurance  
**Expertise:** XCTest, UI Testing, Performance Testing

### Responsibilities
- Write unit tests for core functionality
- Implement UI tests for critical paths
- Create performance benchmarks
- Set up CI/CD pipeline
- Maintain test coverage > 80%

### Test Categories
- **Unit Tests:** Document model, tab management, syntax highlighting
- **UI Tests:** Tab operations, file operations, keyboard shortcuts
- **Performance Tests:** Launch time, file loading, typing responsiveness

---

## 9. Build & Deploy Agent

**Role:** Build System & Distribution  
**Expertise:** Xcode, xcodebuild, App Store Connect

### Responsibilities
- Configure build settings for all platforms
- Create Makefile for CLI builds
- Set up code signing
- Prepare for App Store submission
- Manage versioning

### Build Targets
- macOS (primary)
- iOS (iPhone)
- iPadOS (iPad)

### Makefile Commands
```bash
make clean      # Clean build artifacts
make build-mac  # Build for macOS
make build-ios  # Build for iOS (iPhone/iPad)
make deploy     # Deploy to devices/simulators
make all        # Full build for all platforms
```

---

## 10. Documentation Agent

**Role:** Technical Documentation  
**Expertise:** Markdown, DocC, Technical Writing

### Responsibilities
- Maintain code documentation
- Write API references
- Create user guides
- Document architecture decisions
- Keep README up to date

### Deliverables
- Code comments and DocC documentation
- Architecture Decision Records (ADRs)
- User manual
- Changelog

---

## Agent Collaboration Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                    Swift Architect Agent                     │
│              (Overall Architecture & Design)                 │
└─────────────────────────┬───────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│  Text Engine  │ │  Tab Manager  │ │   UX/UI       │
│    Agent      │ │    Agent      │ │   Agent       │
└───────┬───────┘ └───────┬───────┘ └───────┬───────┘
        │                 │                 │
        └─────────────────┼─────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│    File Ops   │ │  Performance  │ │ Accessibility │
│    Agent      │ │    Agent      │ │    Agent      │
└───────────────┘ └───────────────┘ └───────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│   Testing     │ │ Build/Deploy  │ │ Documentation │
│    Agent      │ │    Agent      │ │    Agent      │
└───────────────┘ └───────────────┘ └───────────────┘
```

---

## Phase Mapping

### Phase 1 — MVP (Current)
- Swift Architect Agent
- Text Engine Agent
- Tab Manager Agent
- UX/UI Agent
- File Operations Agent
- Build & Deploy Agent

### Phase 2 — Enhancement
- Performance Agent (optimization)
- Accessibility Agent
- Testing Agent
- Documentation Agent

### Phase 3 — Advanced Features
All agents collaborating on:
- AI-assisted writing
- Plugin system
- Git diff viewer
- Spotlight integration

---

## Success Criteria

Each agent must ensure their deliverables meet these standards:

1. **Code Quality:** Swift best practices, no force unwraps, proper error handling
2. **Performance:** Meet all PRD performance targets
3. **Accessibility:** VoiceOver compatible, keyboard navigable
4. **Testing:** Unit test coverage > 80%
5. **Documentation:** Inline comments, DocC ready

---

*Document Version: 1.0*  
*Last Updated: January 2026*
