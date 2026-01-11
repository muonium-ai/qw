//
//  EditorSettings.swift
//  qw
//
//  Editor settings and configuration
//

import SwiftUI
import Combine

/// Available programming fonts
enum ProgrammingFont: String, CaseIterable, Identifiable {
    case system = "System Mono"
    case sfMono = "SF Mono"
    case menlo = "Menlo"
    case monaco = "Monaco"
    case courier = "Courier New"
    case sourceCodePro = "Source Code Pro"
    case jetBrainsMono = "JetBrains Mono"
    case firaCode = "Fira Code"
    case hack = "Hack"
    case inconsolata = "Inconsolata"
    
    var id: String { rawValue }
    
    var fontName: String {
        switch self {
        case .system: return "Menlo" // Fallback for system mono
        case .sfMono: return "SFMono-Regular"
        case .menlo: return "Menlo"
        case .monaco: return "Monaco"
        case .courier: return "Courier New"
        case .sourceCodePro: return "SourceCodePro-Regular"
        case .jetBrainsMono: return "JetBrainsMono-Regular"
        case .firaCode: return "FiraCode-Regular"
        case .hack: return "Hack-Regular"
        case .inconsolata: return "Inconsolata-Regular"
        }
    }
    
    var displayName: String { rawValue }
    
    /// Check if font is available on the system
    var isAvailable: Bool {
        #if os(macOS)
        return NSFont(name: fontName, size: 12) != nil || self == .system
        #else
        return UIFont(name: fontName, size: 12) != nil || self == .system
        #endif
    }
    
    /// Get available fonts only
    static var availableFonts: [ProgrammingFont] {
        allCases.filter { $0.isAvailable }
    }
}

/// Editor theme names
enum EditorThemeName: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    case solarizedLight = "Solarized Light"
    case solarizedDark = "Solarized Dark"
    case monokai = "Monokai"
    case dracula = "Dracula"
    case nord = "Nord"
    case oneDark = "One Dark"
    case github = "GitHub"
    
    var id: String { rawValue }
}

/// Global editor settings manager
class EditorSettingsManager: ObservableObject {
    static let shared = EditorSettingsManager()
    
    // Font settings
    @AppStorage("editorFontName") var fontName: String = ProgrammingFont.system.rawValue {
        didSet { objectWillChange.send() }
    }
    @AppStorage("editorFontSize") var fontSize: Double = 14 {
        didSet { objectWillChange.send() }
    }
    
    // Theme settings
    @AppStorage("editorTheme") var themeName: String = EditorThemeName.system.rawValue {
        didSet { objectWillChange.send() }
    }
    
    // Display settings
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = true {
        didSet { objectWillChange.send() }
    }
    @AppStorage("lineHeight") var lineHeight: Double = 1.4 {
        didSet { objectWillChange.send() }
    }
    @AppStorage("tabWidth") var tabWidth: Int = 4 {
        didSet { objectWillChange.send() }
    }
    @AppStorage("insertSpacesForTab") var insertSpacesForTab: Bool = true {
        didSet { objectWillChange.send() }
    }
    @AppStorage("wordWrap") var wordWrap: Bool = true {
        didSet { objectWillChange.send() }
    }
    
    var selectedFont: ProgrammingFont {
        ProgrammingFont(rawValue: fontName) ?? .system
    }
    
    var selectedTheme: EditorThemeName {
        EditorThemeName(rawValue: themeName) ?? .system
    }
    
    func increaseFontSize() {
        if fontSize < 32 {
            fontSize += 1
        }
    }
    
    func decreaseFontSize() {
        if fontSize > 8 {
            fontSize -= 1
        }
    }
    
    #if os(macOS)
    func nsFont() -> NSFont {
        if selectedFont == .system {
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        return NSFont(name: selectedFont.fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
    #else
    func uiFont() -> UIFont {
        if selectedFont == .system {
            return UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        return UIFont(name: selectedFont.fontName, size: fontSize)
            ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
    #endif
    
    /// Get the syntax theme based on current settings
    func syntaxTheme(for colorScheme: ColorScheme) -> SyntaxTheme {
        switch selectedTheme {
        case .system:
            return colorScheme == .dark ? .dark : .light
        case .light:
            return .light
        case .dark:
            return .dark
        case .solarizedLight:
            return .solarizedLight
        case .solarizedDark:
            return .solarizedDark
        case .monokai:
            return .monokai
        case .dracula:
            return .dracula
        case .nord:
            return .nord
        case .oneDark:
            return .oneDark
        case .github:
            return .github
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let editorSettingsChanged = Notification.Name("editorSettingsChanged")
    static let increaseFontSize = Notification.Name("increaseFontSize")
    static let decreaseFontSize = Notification.Name("decreaseFontSize")
}
