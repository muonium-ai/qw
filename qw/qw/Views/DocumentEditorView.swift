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
    
    @State private var fileType: SupportedFileType = .plainText
    @State private var isReadOnly: Bool = false
    @StateObject private var searchState = SearchState()
    
    var body: some View {
        VStack(spacing: 0) {
            // Search/Replace bar
            if searchState.isVisible {
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
                    }
                )
                .onChange(of: searchState.searchText) { _, _ in
                    searchState.findMatches(in: document.text)
                }
            }
            
            // Editor
            CodeEditorView(
                text: $document.text,
                fileType: fileType,
                isReadOnly: isReadOnly
            )
            .accessibilityIdentifier("documentEditor")
        }
        .onAppear {
            updateFileType()
            // Check if this file was opened in read-only mode from CLI
            if let url = fileURL {
                #if os(macOS)
                if ReadOnlyFileManager.shared.isReadOnly(url: url) {
                    isReadOnly = true
                } else {
                    isReadOnly = initialReadOnly
                }
                #else
                isReadOnly = initialReadOnly
                #endif
            } else {
                isReadOnly = initialReadOnly
            }
        }
        .onChange(of: fileURL) { _, _ in
            updateFileType()
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
        #endif
    }
    
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
                    print("Error saving file: \(error)")
                }
            }
        }
    }
    
    private func printDocument() {
        let settings = EditorSettingsManager.shared
        let exporter = DocumentExporter(
            text: document.text,
            fileType: fileType,
            theme: settings.syntaxTheme(for: .light), // Use light theme for printing
            includeLineNumbers: settings.showLineNumbers,
            fontSize: settings.fontSize,
            fontName: settings.selectedFont.fontName
        )
        exporter.print()
    }
    
    private func exportAsPDF() {
        let settings = EditorSettingsManager.shared
        let exporter = DocumentExporter(
            text: document.text,
            fileType: fileType,
            theme: settings.syntaxTheme(for: .light), // Use light theme for PDF
            includeLineNumbers: settings.showLineNumbers,
            fontSize: settings.fontSize,
            fontName: settings.selectedFont.fontName
        )
        
        let defaultName = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        exporter.showPDFExportDialog(defaultName: defaultName)
    }
    
    private func exportAsPNG() {
        let settings = EditorSettingsManager.shared
        let exporter = DocumentExporter(
            text: document.text,
            fileType: fileType,
            theme: settings.syntaxTheme(for: .light), // Use light theme for PNG
            includeLineNumbers: settings.showLineNumbers,
            fontSize: settings.fontSize,
            fontName: settings.selectedFont.fontName
        )
        
        let defaultName = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
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
}

/// Document scene for the app
struct QWDocumentScene: Scene {
    var body: some Scene {
        DocumentGroup(newDocument: TextDocument()) { file in
            DocumentEditorView(
                document: file.$document,
                fileURL: file.fileURL
            )
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 400)
            #endif
        }
    }
}

#Preview {
    DocumentEditorView(
        document: .constant(TextDocument(text: "Hello, World!", fileType: .plainText)),
        fileURL: nil
    )
}
