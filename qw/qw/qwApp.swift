//
//  qwApp.swift
//  qw
//
//  Created by Senthil Nayagam on 10/01/26.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct qwApp: App {
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
            // File menu customizations
            CommandGroup(after: .newItem) {
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

