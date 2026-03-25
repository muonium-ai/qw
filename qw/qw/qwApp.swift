//
//  qwApp.swift
//  qw
//
//  Created by Senthil Nayagam on 10/01/26.
//

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit

/// Shared manager for tracking read-only file requests from CLI
class ReadOnlyFileManager {
    static let shared = ReadOnlyFileManager()
    private var readOnlyFiles: Set<String> = []
    private var writableFiles: Set<String> = []
    
    private init() {
        loadPendingReadOnlyFiles()
    }
    
    private func loadPendingReadOnlyFiles() {
        // Check if there's a pending read-only files list from CLI
        if let listPath = UserDefaults.standard.string(forKey: "pendingReadOnlyFiles") {
            if let contents = try? String(contentsOfFile: listPath, encoding: .utf8) {
                let files = contents.components(separatedBy: "\n").filter { !$0.isEmpty }
                readOnlyFiles = Set(files)
            }
            // Clear the pending list
            UserDefaults.standard.removeObject(forKey: "pendingReadOnlyFiles")
            // Remove the temp file
            try? FileManager.default.removeItem(atPath: listPath)
        }
    }
    
    func isReadOnly(url: URL) -> Bool {
        return readOnlyFiles.contains(url.path)
    }

    func isWritable(url: URL) -> Bool {
        return writableFiles.contains(url.path)
    }
    
    func markAsReadOnly(url: URL) {
        readOnlyFiles.insert(url.path)
        writableFiles.remove(url.path)
    }

    func markAsWritable(url: URL) {
        writableFiles.insert(url.path)
        readOnlyFiles.remove(url.path)
    }
    
    func removeReadOnly(url: URL) {
        readOnlyFiles.remove(url.path)
    }

    func removeWritable(url: URL) {
        writableFiles.remove(url.path)
    }
}

/// App delegate to handle application lifecycle events
class QWAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize read-only file manager to check for CLI-passed files
        _ = ReadOnlyFileManager.shared
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSDocumentController.shared.newDocument(nil)
        }
        return true
    }
}
#endif

@main
struct qwApp: App {
    @FocusedValue(\.searchState) private var searchState
    @FocusedValue(\.documentPrintAction) private var documentPrintAction
    @FocusedValue(\.documentExportAction) private var documentExportAction
    @FocusedValue(\.documentExportPDFAction) private var documentExportPDFAction
    @FocusedValue(\.documentExportPNGAction) private var documentExportPNGAction
    @FocusedValue(\.toggleReadOnlyAction) private var toggleReadOnlyAction
    @FocusedValue(\.isReadOnly) private var isReadOnly
    @FocusedValue(\.toggleHexModeAction) private var toggleHexModeAction
    @FocusedValue(\.isHexMode) private var isHexMode
    @FocusedValue(\.hexCompareAction) private var hexCompareAction
    @FocusedValue(\.currentFileURL) private var currentFileURL

    #if os(macOS)
    @NSApplicationDelegateAdaptor(QWAppDelegate.self) var appDelegate
    #endif
    
    var body: some Scene {
        // Document-based scene for file editing
        DocumentGroup(newDocument: TextDocument()) { file in
            DocumentEditorView(
                document: file.$document,
                fileURL: file.fileURL,
                initialReadOnly: true
            )
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 400)
            #endif
        }
        #if os(macOS)
        .commands {
            // File menu - Open Writable (default is read-only)
            CommandGroup(after: .newItem) {
                Button("Open Writable...") {
                    openWritableFile()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            
            // File menu - Close, Revert, Duplicate
            CommandGroup(before: .saveItem) {
                Button("Close") {
                    NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()
            }

            // File menu - Save (disable when read-only)
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    // Use standard save action
                    NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isReadOnly == true)
                
                Button("Save As...") {
                    NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(isReadOnly == true)
                
                Divider()
                
                Button("Export As...") {
                    if let action = documentExportAction {
                        action()
                    } else {
                        NSSound.beep()
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Export as PDF...") {
                    if let action = documentExportPDFAction {
                        action()
                    } else {
                        NSSound.beep()
                    }
                }
                
                Button("Export as PNG...") {
                    if let action = documentExportPNGAction {
                        action()
                    } else {
                        NSSound.beep()
                    }
                }

                Divider()

                Button("Revert to Saved") {
                    NSApp.sendAction(#selector(NSDocument.revertToSaved(_:)), to: nil, from: nil)
                }

                Divider()

                Button("Duplicate Window") {
                    duplicateWindow()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(currentFileURL == nil)
            }
            
            // File menu - Print
            CommandGroup(replacing: .printItem) {
                Button("Print...") {
                    if let action = documentPrintAction {
                        action()
                    } else {
                        NSSound.beep()
                    }
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            
            // Find menu
            CommandGroup(replacing: .textEditing) {
                Button("Find...") {
                    searchState?.isVisible = true
                    searchState?.showReplace = false
                }
                .keyboardShortcut("f", modifiers: .command)
                
                Button("Find and Replace...") {
                    searchState?.isVisible = true
                    searchState?.showReplace = true
                }
                .keyboardShortcut("h", modifiers: .command)
                
                Button("Find Next") {
                    searchState?.findNext()
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(searchState?.matches.isEmpty ?? true)
                
                Button("Find Previous") {
                    searchState?.findPrevious()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(searchState?.matches.isEmpty ?? true)
                
                Divider()
            }
            
            // Editor menu
            CommandMenu("Editor") {
                Button("Increase Font Size") {
                    EditorSettingsManager.shared.increaseFontSize()
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Decrease Font Size") {
                    EditorSettingsManager.shared.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Divider()
                
                Button("Toggle Line Numbers") {
                    EditorSettingsManager.shared.showLineNumbers.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                
                Toggle("Word Wrap", isOn: Binding(
                    get: { EditorSettingsManager.shared.wordWrap },
                    set: { EditorSettingsManager.shared.wordWrap = $0 }
                ))
                .keyboardShortcut("w", modifiers: [.command, .option])
                
                Divider()
                
                Button(isReadOnly == true ? "✓ Read Only" : "Read Only") {
                    toggleReadOnlyAction?()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button(isHexMode == true ? "✓ Hex Mode" : "Hex Mode") {
                    toggleHexModeAction?()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button("Compare With...") {
                    if let action = hexCompareAction {
                        action()
                    } else {
                        NSSound.beep()
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(isHexMode != true)
            }
        }
        #endif
        
        #if os(macOS)
        // Settings window for macOS
        Settings {
            SettingsView()
        }
        #endif
    }
    
    #if os(macOS)
    /// Open a file in read-only mode via file picker
    private func openWritableFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = TextDocument.readableContentTypes
        openPanel.message = "Select file(s) to open in write mode"
        openPanel.prompt = "Open Writable"
        
        openPanel.begin { response in
            if response == .OK {
                for url in openPanel.urls {
                    // Mark the file as writable before opening
                    ReadOnlyFileManager.shared.markAsWritable(url: url)
                    
                    // Open the document
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                        if let error = error {
                            print("Error opening document: \(error)")
                        }
                    }
                }
            }
        }
    }
    /// Open a new window with the same file loaded
    private func duplicateWindow() {
        guard let url = currentFileURL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error = error {
                print("Error duplicating window: \(error)")
            }
        }
    }
    #endif
}

// MARK: - Notifications
extension Notification.Name {
    static let exportDocument = Notification.Name("exportDocument")
    static let printDocument = Notification.Name("printDocument")
    static let exportPDF = Notification.Name("exportPDF")
    static let exportPNG = Notification.Name("exportPNG")
}

// MARK: - Settings View
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
            
            FontSettingsView()
                .tabItem {
                    Label("Font", systemImage: "textformat")
                }
            
            EditorSettingsView()
                .tabItem {
                    Label("Editor", systemImage: "text.alignleft")
                }
        }
        .frame(width: 500, height: 350)
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject private var settings = EditorSettingsManager.shared
    
    var body: some View {
        Form {
            Section("Theme") {
                Picker("Color Theme", selection: $settings.themeName) {
                    ForEach(EditorThemeName.allCases) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #endif
            }
            
            Section("Display") {
                Toggle("Show Line Numbers", isOn: $settings.showLineNumbers)
            }
        }
        .padding()
    }
}

struct FontSettingsView: View {
    @ObservedObject private var settings = EditorSettingsManager.shared
    
    var body: some View {
        Form {
            Section("Font Family") {
                Picker("Font", selection: $settings.fontName) {
                    ForEach(ProgrammingFont.availableFonts) { font in
                        Text(font.displayName).tag(font.rawValue)
                    }
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #endif
            }
            
            Section("Font Size") {
                HStack {
                    Text("Size: \(Int(settings.fontSize)) pt")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $settings.fontSize, in: 8...32, step: 1)
                    
                    Button("-") {
                        settings.decreaseFontSize()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("+") {
                        settings.increaseFontSize()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Section("Preview") {
                Text("The quick brown fox jumps over the lazy dog")
                    .font(.custom(settings.selectedFont.fontName, size: settings.fontSize))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}

struct EditorSettingsView: View {
    @ObservedObject private var settings = EditorSettingsManager.shared
    
    var body: some View {
        Form {
            Section("Indentation") {
                Stepper("Tab Width: \(settings.tabWidth)", value: $settings.tabWidth, in: 2...8)
                Toggle("Insert Spaces for Tabs", isOn: $settings.insertSpacesForTab)
            }
            
            Section("Text") {
                Toggle("Word Wrap", isOn: $settings.wordWrap)
                
                HStack {
                    Text("Line Height: \(String(format: "%.1f", settings.lineHeight))")
                    Slider(value: $settings.lineHeight, in: 1.0...2.0, step: 0.1)
                }
            }
        }
        .padding()
    }
}

