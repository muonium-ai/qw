//
//  DocumentEditorView.swift
//  qw
//
//  Document editor view for editing text documents
//

import SwiftUI
import UniformTypeIdentifiers

/// The main document editor view
struct DocumentEditorView: View {
    @Binding var document: TextDocument
    var fileURL: URL?
    
    @State private var fileType: SupportedFileType = .plainText
    
    var body: some View {
        CodeEditorView(
            text: $document.text,
            fileType: fileType
        )
        .accessibilityIdentifier("documentEditor")
        .onAppear {
            updateFileType()
        }
        .onChange(of: fileURL) { _, _ in
            updateFileType()
        }
    }
    
    private func updateFileType() {
        if let url = fileURL {
            fileType = SupportedFileType.from(url: url)
        } else {
            fileType = document.fileType
        }
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
