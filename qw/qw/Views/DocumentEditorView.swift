//
//  DocumentEditorView.swift
//  qw
//
//  Document editor view for editing text documents
//

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// The main document editor view
struct DocumentEditorView: View {
    @Binding var document: TextDocument
    var fileURL: URL?
    var initialReadOnly: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var fileType: SupportedFileType = .plainText
    @State private var isReadOnly: Bool = false
    @State private var isHexMode: Bool = false
    @State private var showBinaryAlert: Bool = false
    @StateObject private var searchState = SearchState()

    // Binary diff comparison state
    @State private var isComparing: Bool = false
    @State private var comparisonData: Data?
    @State private var comparisonName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search/Replace bar (hidden in hex mode)
            if searchState.isVisible && !isHexMode {
                SearchReplaceView(
                    searchText: $searchState.searchText,
                    replaceText: $searchState.replaceText,
                    isVisible: $searchState.isVisible,
                    showReplace: $searchState.showReplace,
                    onFindNext: {
                        searchState.findNext()
                    },
                    onFindPrevious: {
                        searchState.findPrevious()
                    },
                    onReplace: {
                        if !isReadOnly {
                            searchState.replace(in: &document.text)
                        }
                    },
                    onReplaceAll: {
                        if !isReadOnly {
                            searchState.replaceAll(in: &document.text)
                        }
                    },
                    matchCount: searchState.matches.count,
                    currentMatchIndex: searchState.currentMatchIndex
                )
                .onChange(of: searchState.searchText) { _, _ in
                    searchState.findMatches(in: document.text)
                }
            }

            // Editor or Hex View
            if isHexMode && isComparing, let compData = comparisonData {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Close Comparison") {
                            isComparing = false
                            comparisonData = nil
                            comparisonName = ""
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    .background {
                        #if os(macOS)
                        Color(nsColor: .windowBackgroundColor)
                        #else
                        Color(uiColor: .secondarySystemBackground)
                        #endif
                    }
                    HexDiffView(
                        dataA: document.rawData,
                        dataB: compData,
                        nameA: fileURL?.lastPathComponent ?? "Current File",
                        nameB: comparisonName
                    )
                }
                .accessibilityIdentifier("hexDiffViewer")
            } else if isHexMode {
                HexView(data: document.rawData)
                    .accessibilityIdentifier("hexViewer")
            } else {
                CodeEditorView(
                    text: $document.text,
                    fileType: fileType,
                    fileName: fileURL?.lastPathComponent,
                    isReadOnly: isReadOnly,
                    searchState: searchState
                )
                .accessibilityIdentifier("documentEditor")
            }
        }
        #if os(macOS)
        .background(WindowTitleModeUpdater(isReadOnly: isReadOnly, isHexMode: isHexMode))
        #endif
        .onAppear {
            updateFileType()
            // Check if this file was opened in read-only mode from CLI
            if let url = fileURL {
                #if os(macOS)
                if ReadOnlyFileManager.shared.isWritable(url: url) {
                    isReadOnly = false
                } else if ReadOnlyFileManager.shared.isReadOnly(url: url) {
                    isReadOnly = true
                } else {
                    isReadOnly = initialReadOnly
                }
                #else
                isReadOnly = initialReadOnly
                #endif
            } else {
                // New untitled documents should start writable
                isReadOnly = false
            }

            // Auto-detect binary files and prompt for hex mode
            if document.isBinaryDetected {
                showBinaryAlert = true
            }
        }
        .onChange(of: fileURL) { _, _ in
            updateFileType()
        }
        .alert("Binary File Detected", isPresented: $showBinaryAlert) {
            Button("Hex Mode") {
                isHexMode = true
            }
            Button("Text Mode", role: .cancel) {
                isHexMode = false
            }
        } message: {
            Text("This file appears to be binary. Open in hex mode?")
        }
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { searchState.isVisible.toggle() }) {
                    Image(systemName: "magnifyingglass")
                }
                .help("Find (⌘F)")
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityIdentifier("toggleSearchButton")
            }
        }
        #endif
        .focusedSceneValue(\.searchState, searchState)
        #if os(macOS)
        .focusedSceneValue(\.documentExportAction, { exportDocument() })
        .focusedSceneValue(\.documentPrintAction, { printDocument() })
        .focusedSceneValue(\.documentExportPDFAction, { exportAsPDF() })
        .focusedSceneValue(\.documentExportPNGAction, { exportAsPNG() })
        .focusedSceneValue(\.toggleReadOnlyAction, { isReadOnly.toggle() })
        .focusedSceneValue(\.isReadOnly, isReadOnly)
        .focusedSceneValue(\.toggleHexModeAction, { isHexMode.toggle() })
        .focusedSceneValue(\.isHexMode, isHexMode)
        .focusedSceneValue(\.hexCompareAction, { openComparePanel() })
        #endif
    }

        #if os(macOS)
        private struct WindowTitleModeUpdater: NSViewRepresentable {
            let isReadOnly: Bool
            let isHexMode: Bool

            func makeNSView(context: Context) -> NSView {
                let view = NSView(frame: .zero)
                DispatchQueue.main.async {
                    updateWindowTitle(for: view.window)
                }
                return view
            }

            func updateNSView(_ nsView: NSView, context: Context) {
                DispatchQueue.main.async {
                    updateWindowTitle(for: nsView.window)
                }
            }

            private func updateWindowTitle(for window: NSWindow?) {
                guard let window = window else { return }
                var modeText = isReadOnly ? "Read Only" : "Write"
                if isHexMode {
                    modeText = "Hex — \(modeText)"
                }
                if #available(macOS 11.0, *) {
                    window.subtitle = modeText
                } else {
                    let baseTitle = stripModeSuffix(from: window.title)
                    window.title = "\(baseTitle) — \(modeText)"
                }
            }

            private func stripModeSuffix(from title: String) -> String {
                let suffixes = [" — Read Only", " — Write", " — Hex — Read Only", " — Hex — Write"]
                for suffix in suffixes where title.hasSuffix(suffix) {
                    return String(title.dropLast(suffix.count))
                }
                return title
            }
        }
        #endif
    
    #if os(macOS)
    private func openComparePanel() {
        guard isHexMode else {
            NSSound.beep()
            return
        }
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.message = "Select a file to compare with"
        openPanel.prompt = "Compare"

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    comparisonData = data
                    comparisonName = url.lastPathComponent
                    isComparing = true
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Compare Error"
                    alert.informativeText = "Failed to read file: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    #endif

    private func updateFileType() {
        if let url = fileURL {
            fileType = SupportedFileType.from(url: url)
        } else {
            fileType = document.fileType
        }
    }
    
    #if os(macOS)
    private func exportDocument() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = TextDocument.writableContentTypes
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save As"
        savePanel.message = "Choose a location to save your file"
        savePanel.nameFieldLabel = "File Name:"
        
        // Set default filename from current file or use "Untitled"
        if let url = fileURL {
            savePanel.nameFieldStringValue = url.lastPathComponent
        } else {
            savePanel.nameFieldStringValue = "Untitled.\(fileType.rawValue)"
        }
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let data = document.text.data(using: .utf8) ?? Data()
                    try data.write(to: url)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Export Error"
                    alert.informativeText = "Failed to save file: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    private func printDocument() {
        let settings = EditorSettingsManager.shared
        let exporter = DocumentExporter(
            text: document.text,
            fileType: fileType,
            fileName: fileURL?.lastPathComponent,
            theme: settings.syntaxTheme(for: .light), // Intentionally light: prints on paper are most legible with a light background
            includeLineNumbers: settings.showLineNumbers,
            fontSize: settings.fontSize,
            fontName: settings.selectedFont.fontName
        )
        exporter.printDocument()
    }
    
    private func exportAsPDF() {
        let settings = EditorSettingsManager.shared
        let exporter = DocumentExporter(
            text: document.text,
            fileType: fileType,
            fileName: fileURL?.lastPathComponent,
            theme: settings.syntaxTheme(for: colorScheme),
            includeLineNumbers: settings.showLineNumbers,
            fontSize: settings.fontSize,
            fontName: settings.selectedFont.fontName
        )
        
        let defaultName = fileURL?.lastPathComponent ?? "Untitled"
        exporter.showPDFExportDialog(defaultName: defaultName)
    }
    
    private func exportAsPNG() {
        let settings = EditorSettingsManager.shared
        let exporter = DocumentExporter(
            text: document.text,
            fileType: fileType,
            fileName: fileURL?.lastPathComponent,
            theme: settings.syntaxTheme(for: colorScheme),
            includeLineNumbers: settings.showLineNumbers,
            fontSize: settings.fontSize,
            fontName: settings.selectedFont.fontName
        )
        
        let defaultName = fileURL?.lastPathComponent ?? "Untitled"
        exporter.showPNGExportDialog(defaultName: defaultName)
    }
    #endif
}

// MARK: - Focus Values for Search State
struct SearchStateFocusKey: FocusedValueKey {
    typealias Value = SearchState
}

// MARK: - Focus Values for Document Actions (Print/Export)
struct DocumentPrintActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DocumentExportActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DocumentExportPDFActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DocumentExportPNGActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ToggleReadOnlyActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct IsReadOnlyFocusKey: FocusedValueKey {
    typealias Value = Bool
}

struct ToggleHexModeActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct IsHexModeFocusKey: FocusedValueKey {
    typealias Value = Bool
}

struct HexCompareActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var searchState: SearchState? {
        get { self[SearchStateFocusKey.self] }
        set { self[SearchStateFocusKey.self] = newValue }
    }

    var documentPrintAction: (() -> Void)? {
        get { self[DocumentPrintActionFocusKey.self] }
        set { self[DocumentPrintActionFocusKey.self] = newValue }
    }

    var documentExportAction: (() -> Void)? {
        get { self[DocumentExportActionFocusKey.self] }
        set { self[DocumentExportActionFocusKey.self] = newValue }
    }

    var documentExportPDFAction: (() -> Void)? {
        get { self[DocumentExportPDFActionFocusKey.self] }
        set { self[DocumentExportPDFActionFocusKey.self] = newValue }
    }

    var documentExportPNGAction: (() -> Void)? {
        get { self[DocumentExportPNGActionFocusKey.self] }
        set { self[DocumentExportPNGActionFocusKey.self] = newValue }
    }
    
    var toggleReadOnlyAction: (() -> Void)? {
        get { self[ToggleReadOnlyActionFocusKey.self] }
        set { self[ToggleReadOnlyActionFocusKey.self] = newValue }
    }
    
    var isReadOnly: Bool? {
        get { self[IsReadOnlyFocusKey.self] }
        set { self[IsReadOnlyFocusKey.self] = newValue }
    }

    var toggleHexModeAction: (() -> Void)? {
        get { self[ToggleHexModeActionFocusKey.self] }
        set { self[ToggleHexModeActionFocusKey.self] = newValue }
    }

    var isHexMode: Bool? {
        get { self[IsHexModeFocusKey.self] }
        set { self[IsHexModeFocusKey.self] = newValue }
    }

    var hexCompareAction: (() -> Void)? {
        get { self[HexCompareActionFocusKey.self] }
        set { self[HexCompareActionFocusKey.self] = newValue }
    }
}

#Preview {
    DocumentEditorView(
        document: .constant(TextDocument(text: "Hello, World!", fileType: .plainText)),
        fileURL: nil
    )
}
