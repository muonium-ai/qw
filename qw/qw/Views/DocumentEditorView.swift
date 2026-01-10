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
    
    @State private var fileType: SupportedFileType = .plainText
    @StateObject private var searchState = SearchState()
    @State private var showExportSheet = false
    
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
                        searchState.replace(in: &document.text)
                    },
                    onReplaceAll: {
                        searchState.replaceAll(in: &document.text)
                    }
                )
                .onChange(of: searchState.searchText) { _, _ in
                    searchState.findMatches(in: document.text)
                }
            }
            
            // Editor
            CodeEditorView(
                text: $document.text,
                fileType: fileType
            )
            .accessibilityIdentifier("documentEditor")
        }
        .onAppear {
            updateFileType()
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
        .onReceive(NotificationCenter.default.publisher(for: .exportDocument)) { _ in
            exportDocument()
        }
        #endif
        .focusedSceneValue(\.searchState, searchState)
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
    #endif
}

// MARK: - Focus Values for Search State
struct SearchStateFocusKey: FocusedValueKey {
    typealias Value = SearchState
}

extension FocusedValues {
    var searchState: SearchState? {
        get { self[SearchStateFocusKey.self] }
        set { self[SearchStateFocusKey.self] = newValue }
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
