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
            // File menu customizations - Save As via export
            CommandGroup(after: .saveItem) {
                Button("Export As...") {
                    NotificationCenter.default.post(name: .exportDocument, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
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
                    // TODO: Implement font size increase
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Decrease Font Size") {
                    // TODO: Implement font size decrease
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Divider()
                
                Button("Toggle Line Numbers") {
                    // TODO: Implement line numbers toggle
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
}

// MARK: - Settings View
struct SettingsView: View {
    @AppStorage("editorFontSize") private var fontSize: Double = 14
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = true
    @AppStorage("editorTheme") private var editorTheme: String = "system"
    
    var body: some View {
        TabView {
            GeneralSettingsView(
                fontSize: $fontSize,
                showLineNumbers: $showLineNumbers,
                editorTheme: $editorTheme
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            EditorSettingsView()
            .tabItem {
                Label("Editor", systemImage: "text.alignleft")
            }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @Binding var fontSize: Double
    @Binding var showLineNumbers: Bool
    @Binding var editorTheme: String
    
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $editorTheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            
            Section("Font") {
                HStack {
                    Text("Size: \(Int(fontSize))")
                    Slider(value: $fontSize, in: 10...24, step: 1)
                }
            }
            
            Section("Display") {
                Toggle("Show Line Numbers", isOn: $showLineNumbers)
            }
        }
        .padding()
    }
}

struct EditorSettingsView: View {
    @AppStorage("tabWidth") private var tabWidth: Int = 4
    @AppStorage("insertSpacesForTab") private var insertSpacesForTab: Bool = true
    @AppStorage("autoIndent") private var autoIndent: Bool = true
    @AppStorage("wordWrap") private var wordWrap: Bool = true
    
    var body: some View {
        Form {
            Section("Indentation") {
                Stepper("Tab Width: \(tabWidth)", value: $tabWidth, in: 2...8)
                Toggle("Insert Spaces for Tabs", isOn: $insertSpacesForTab)
                Toggle("Auto Indent", isOn: $autoIndent)
            }
            
            Section("Text") {
                Toggle("Word Wrap", isOn: $wordWrap)
            }
        }
        .padding()
    }
}

