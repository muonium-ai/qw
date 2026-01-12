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

/// App delegate to handle application lifecycle events
class QWAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create a new document on launch if no documents are open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.newDocument(nil)
            }
        }
    }
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.newDocument(nil)
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
    
    #if os(macOS)
    @NSApplicationDelegateAdaptor(QWAppDelegate.self) var appDelegate
    #endif
    
    var body: some Scene {
        // Document-based scene for file editing
        DocumentGroup(newDocument: TextDocument()) { file in
            DocumentEditorView(
                document: file.$document,
                fileURL: file.fileURL
            )
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 400)
            #endif
        }
        #if os(macOS)
        .commands {
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
            
            // File menu - Export options
            CommandGroup(after: .saveItem) {
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

