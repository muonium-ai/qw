#!/usr/bin/env swift
//
//  qw-export.swift
//  qw-export
//
//  Standalone command-line tool for exporting source code as PNG/PDF
//  with syntax highlighting - exactly as it appears in QW Editor
//
//  Usage: swift qw-export.swift [options] <input-file>
//  Or compile: swiftc -O -o qw-export qw-export.swift -framework AppKit
//
//  Copyright (c) 2024 Muonium AI. MIT License.
//

import Foundation
import AppKit

// MARK: - Token Types

enum TokenType {
    case plain, keyword, string, number, comment
    case function, type, property, tag, attribute
    case punctuation, heading, link, emphasis, codeBlock
}

struct Token {
    let range: Range<String.Index>
    let type: TokenType
}

// MARK: - Supported File Types

enum SupportedFileType: String, CaseIterable {
    case plainText = "txt"
    case markdown = "md"
    case json = "json"
    case yaml = "yaml"
    case yml = "yml"
    case python = "py"
    case javascript = "js"
    case html = "html"
    case css = "css"
    case swift = "swift"
    
    static func from(extension ext: String) -> SupportedFileType {
        return SupportedFileType(rawValue: ext.lowercased()) ?? .plainText
    }
    
    static func from(url: URL) -> SupportedFileType {
        return from(extension: url.pathExtension)
    }
}

// MARK: - Syntax Theme

struct SyntaxTheme {
    let plain: NSColor
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let function: NSColor
    let type: NSColor
    let property: NSColor
    let tag: NSColor
    let attribute: NSColor
    let punctuation: NSColor
    let heading: NSColor
    let link: NSColor
    let emphasis: NSColor
    let codeBlock: NSColor
    let background: NSColor
    let lineNumber: NSColor
    let gutterBackground: NSColor
    
    static let dark = SyntaxTheme(
        plain: NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1),
        keyword: NSColor(red: 0.9, green: 0.5, blue: 0.8, alpha: 1),
        string: NSColor(red: 0.9, green: 0.6, blue: 0.5, alpha: 1),
        number: NSColor(red: 0.6, green: 0.8, blue: 0.9, alpha: 1),
        comment: NSColor(red: 0.5, green: 0.6, blue: 0.5, alpha: 1),
        function: NSColor(red: 0.5, green: 0.7, blue: 0.9, alpha: 1),
        type: NSColor(red: 0.7, green: 0.6, blue: 0.9, alpha: 1),
        property: NSColor(red: 0.6, green: 0.7, blue: 0.8, alpha: 1),
        tag: NSColor(red: 0.9, green: 0.5, blue: 0.5, alpha: 1),
        attribute: NSColor(red: 0.9, green: 0.7, blue: 0.5, alpha: 1),
        punctuation: NSColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1),
        heading: NSColor(red: 0.5, green: 0.7, blue: 0.9, alpha: 1),
        link: NSColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 1),
        emphasis: NSColor(red: 0.8, green: 0.6, blue: 0.8, alpha: 1),
        codeBlock: NSColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1),
        background: NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1),
        lineNumber: NSColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1),
        gutterBackground: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    )
    
    static let light = SyntaxTheme(
        plain: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
        keyword: NSColor(red: 0.6, green: 0.2, blue: 0.6, alpha: 1),
        string: NSColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1),
        number: NSColor(red: 0.1, green: 0.4, blue: 0.7, alpha: 1),
        comment: NSColor(red: 0.4, green: 0.5, blue: 0.4, alpha: 1),
        function: NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1),
        type: NSColor(red: 0.4, green: 0.3, blue: 0.6, alpha: 1),
        property: NSColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
        tag: NSColor(red: 0.6, green: 0.2, blue: 0.2, alpha: 1),
        attribute: NSColor(red: 0.5, green: 0.3, blue: 0.1, alpha: 1),
        punctuation: NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1),
        heading: NSColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1),
        link: NSColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1),
        emphasis: NSColor(red: 0.4, green: 0.2, blue: 0.4, alpha: 1),
        codeBlock: NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1),
        background: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
        lineNumber: NSColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1),
        gutterBackground: NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
    )
    
    static let monokai = SyntaxTheme(
        plain: NSColor(red: 0.973, green: 0.973, blue: 0.949, alpha: 1),
        keyword: NSColor(red: 0.984, green: 0.149, blue: 0.447, alpha: 1),
        string: NSColor(red: 0.902, green: 0.859, blue: 0.455, alpha: 1),
        number: NSColor(red: 0.682, green: 0.506, blue: 1.000, alpha: 1),
        comment: NSColor(red: 0.467, green: 0.451, blue: 0.404, alpha: 1),
        function: NSColor(red: 0.400, green: 0.851, blue: 0.937, alpha: 1),
        type: NSColor(red: 0.400, green: 0.851, blue: 0.937, alpha: 1),
        property: NSColor(red: 0.973, green: 0.973, blue: 0.949, alpha: 1),
        tag: NSColor(red: 0.984, green: 0.149, blue: 0.447, alpha: 1),
        attribute: NSColor(red: 0.651, green: 0.886, blue: 0.180, alpha: 1),
        punctuation: NSColor(red: 0.973, green: 0.973, blue: 0.949, alpha: 1),
        heading: NSColor(red: 0.682, green: 0.506, blue: 1.000, alpha: 1),
        link: NSColor(red: 0.400, green: 0.851, blue: 0.937, alpha: 1),
        emphasis: NSColor(red: 0.984, green: 0.149, blue: 0.447, alpha: 1),
        codeBlock: NSColor(red: 0.467, green: 0.451, blue: 0.404, alpha: 1),
        background: NSColor(red: 0.153, green: 0.157, blue: 0.133, alpha: 1),
        lineNumber: NSColor(red: 0.467, green: 0.451, blue: 0.404, alpha: 1),
        gutterBackground: NSColor(red: 0.133, green: 0.137, blue: 0.113, alpha: 1)
    )
    
    static let dracula = SyntaxTheme(
        plain: NSColor(red: 0.973, green: 0.973, blue: 0.949, alpha: 1),
        keyword: NSColor(red: 1.000, green: 0.475, blue: 0.776, alpha: 1),
        string: NSColor(red: 0.945, green: 0.980, blue: 0.549, alpha: 1),
        number: NSColor(red: 0.741, green: 0.576, blue: 0.976, alpha: 1),
        comment: NSColor(red: 0.384, green: 0.447, blue: 0.643, alpha: 1),
        function: NSColor(red: 0.314, green: 0.980, blue: 0.482, alpha: 1),
        type: NSColor(red: 0.545, green: 0.914, blue: 0.992, alpha: 1),
        property: NSColor(red: 0.973, green: 0.973, blue: 0.949, alpha: 1),
        tag: NSColor(red: 1.000, green: 0.475, blue: 0.776, alpha: 1),
        attribute: NSColor(red: 0.314, green: 0.980, blue: 0.482, alpha: 1),
        punctuation: NSColor(red: 0.973, green: 0.973, blue: 0.949, alpha: 1),
        heading: NSColor(red: 0.741, green: 0.576, blue: 0.976, alpha: 1),
        link: NSColor(red: 0.545, green: 0.914, blue: 0.992, alpha: 1),
        emphasis: NSColor(red: 1.000, green: 0.475, blue: 0.776, alpha: 1),
        codeBlock: NSColor(red: 0.384, green: 0.447, blue: 0.643, alpha: 1),
        background: NSColor(red: 0.157, green: 0.165, blue: 0.212, alpha: 1),
        lineNumber: NSColor(red: 0.384, green: 0.447, blue: 0.643, alpha: 1),
        gutterBackground: NSColor(red: 0.137, green: 0.145, blue: 0.192, alpha: 1)
    )
    
    static let solarizedDark = SyntaxTheme(
        plain: NSColor(red: 0.514, green: 0.580, blue: 0.588, alpha: 1),
        keyword: NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1),
        string: NSColor(red: 0.165, green: 0.631, blue: 0.596, alpha: 1),
        number: NSColor(red: 0.827, green: 0.212, blue: 0.510, alpha: 1),
        comment: NSColor(red: 0.396, green: 0.482, blue: 0.514, alpha: 1),
        function: NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1),
        type: NSColor(red: 0.710, green: 0.537, blue: 0.000, alpha: 1),
        property: NSColor(red: 0.514, green: 0.580, blue: 0.588, alpha: 1),
        tag: NSColor(red: 0.827, green: 0.212, blue: 0.510, alpha: 1),
        attribute: NSColor(red: 0.710, green: 0.537, blue: 0.000, alpha: 1),
        punctuation: NSColor(red: 0.514, green: 0.580, blue: 0.588, alpha: 1),
        heading: NSColor(red: 0.522, green: 0.600, blue: 0.000, alpha: 1),
        link: NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1),
        emphasis: NSColor(red: 0.827, green: 0.212, blue: 0.510, alpha: 1),
        codeBlock: NSColor(red: 0.396, green: 0.482, blue: 0.514, alpha: 1),
        background: NSColor(red: 0.000, green: 0.169, blue: 0.212, alpha: 1),
        lineNumber: NSColor(red: 0.396, green: 0.482, blue: 0.514, alpha: 1),
        gutterBackground: NSColor(red: 0.000, green: 0.149, blue: 0.192, alpha: 1)
    )
    
    static let solarizedLight = SyntaxTheme(
        plain: NSColor(red: 0.396, green: 0.482, blue: 0.514, alpha: 1),
        keyword: NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1),
        string: NSColor(red: 0.165, green: 0.631, blue: 0.596, alpha: 1),
        number: NSColor(red: 0.827, green: 0.212, blue: 0.510, alpha: 1),
        comment: NSColor(red: 0.576, green: 0.631, blue: 0.631, alpha: 1),
        function: NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1),
        type: NSColor(red: 0.710, green: 0.537, blue: 0.000, alpha: 1),
        property: NSColor(red: 0.396, green: 0.482, blue: 0.514, alpha: 1),
        tag: NSColor(red: 0.827, green: 0.212, blue: 0.510, alpha: 1),
        attribute: NSColor(red: 0.710, green: 0.537, blue: 0.000, alpha: 1),
        punctuation: NSColor(red: 0.396, green: 0.482, blue: 0.514, alpha: 1),
        heading: NSColor(red: 0.522, green: 0.600, blue: 0.000, alpha: 1),
        link: NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1),
        emphasis: NSColor(red: 0.827, green: 0.212, blue: 0.510, alpha: 1),
        codeBlock: NSColor(red: 0.576, green: 0.631, blue: 0.631, alpha: 1),
        background: NSColor(red: 0.992, green: 0.965, blue: 0.890, alpha: 1),
        lineNumber: NSColor(red: 0.576, green: 0.631, blue: 0.631, alpha: 1),
        gutterBackground: NSColor(red: 0.972, green: 0.945, blue: 0.870, alpha: 1)
    )
    
    func color(for tokenType: TokenType) -> NSColor {
        switch tokenType {
        case .plain: return plain
        case .keyword: return keyword
        case .string: return string
        case .number: return number
        case .comment: return comment
        case .function: return function
        case .type: return type
        case .property: return property
        case .tag: return tag
        case .attribute: return attribute
        case .punctuation: return punctuation
        case .heading: return heading
        case .link: return link
        case .emphasis: return emphasis
        case .codeBlock: return codeBlock
        }
    }
}

// MARK: - Syntax Highlighter

class SyntaxHighlighter {
    let fileType: SupportedFileType
    let theme: SyntaxTheme
    
    private static let pythonKeywords = Set([
        "and", "as", "assert", "async", "await", "break", "class", "continue",
        "def", "del", "elif", "else", "except", "False", "finally", "for",
        "from", "global", "if", "import", "in", "is", "lambda", "None",
        "nonlocal", "not", "or", "pass", "raise", "return", "True", "try",
        "while", "with", "yield"
    ])
    
    private static let javascriptKeywords = Set([
        "async", "await", "break", "case", "catch", "class", "const", "continue",
        "debugger", "default", "delete", "do", "else", "export", "extends",
        "false", "finally", "for", "function", "if", "import", "in", "instanceof",
        "let", "new", "null", "return", "static", "super", "switch", "this",
        "throw", "true", "try", "typeof", "undefined", "var", "void", "while", "with", "yield"
    ])
    
    private static let swiftKeywords = Set([
        "actor", "any", "as", "associatedtype", "async", "await", "break", "case",
        "catch", "class", "continue", "default", "defer", "deinit", "do", "else",
        "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for",
        "func", "get", "guard", "if", "import", "in", "init", "inout", "internal",
        "is", "lazy", "let", "mutating", "nil", "nonisolated", "open", "operator",
        "override", "private", "protocol", "public", "repeat", "required", "rethrows",
        "return", "self", "Self", "set", "some", "static", "struct", "subscript",
        "super", "switch", "throw", "throws", "true", "try", "typealias", "var",
        "weak", "where", "while"
    ])
    
    init(fileType: SupportedFileType, theme: SyntaxTheme) {
        self.fileType = fileType
        self.theme = theme
    }
    
    func tokenize(_ text: String) -> [Token] {
        switch fileType {
        case .python: return tokenizePython(text)
        case .javascript: return tokenizeJavaScript(text)
        case .swift: return tokenizeSwift(text)
        case .html: return tokenizeHTML(text)
        case .css: return tokenizeCSS(text)
        case .json: return tokenizeJSON(text)
        case .yaml, .yml: return tokenizeYAML(text)
        case .markdown: return tokenizeMarkdown(text)
        case .plainText: return []
        }
    }
    
    private func tokenizePython(_ text: String) -> [Token] {
        var tokens: [Token] = []
        tokens.append(contentsOf: matchPattern(#"#.*$"#, in: text, type: .comment))
        tokens.append(contentsOf: matchPattern(#"\"\"\"[\s\S]*?\"\"\""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'''[\s\S]*?'''"#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#""[^"\n]*""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'[^'\n]*'"#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"\b\d+\.?\d*\b"#, in: text, type: .number))
        tokens.append(contentsOf: matchKeywords(Self.pythonKeywords, in: text))
        return tokens
    }
    
    private func tokenizeJavaScript(_ text: String) -> [Token] {
        var tokens: [Token] = []
        tokens.append(contentsOf: matchPattern(#"//.*$"#, in: text, type: .comment))
        tokens.append(contentsOf: matchPattern(#"/\*[\s\S]*?\*/"#, in: text, type: .comment))
        tokens.append(contentsOf: matchPattern(#"\"[^\"\n]*\""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'[^'\n]*'"#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"`[^`]*`"#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"\b\d+\.?\d*\b"#, in: text, type: .number))
        tokens.append(contentsOf: matchKeywords(Self.javascriptKeywords, in: text))
        return tokens
    }
    
    private func tokenizeSwift(_ text: String) -> [Token] {
        var tokens: [Token] = []
        tokens.append(contentsOf: matchPattern(#"//.*$"#, in: text, type: .comment))
        tokens.append(contentsOf: matchPattern(#"/\*[\s\S]*?\*/"#, in: text, type: .comment))
        tokens.append(contentsOf: matchPattern(#"\"\"\"[\s\S]*?\"\"\""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#""[^"\n]*""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"\b\d+\.?\d*\b"#, in: text, type: .number))
        tokens.append(contentsOf: matchKeywords(Self.swiftKeywords, in: text))
        tokens.append(contentsOf: matchPattern(#"\b[A-Z][a-zA-Z0-9]*\b"#, in: text, type: .type))
        return tokens
    }
    
    private func tokenizeHTML(_ text: String) -> [Token] {
        var tokens: [Token] = []
        tokens.append(contentsOf: matchPattern(#"<!--[\s\S]*?-->"#, in: text, type: .comment))
        tokens.append(contentsOf: matchPattern(#"</?[a-zA-Z][a-zA-Z0-9]*"#, in: text, type: .tag))
        tokens.append(contentsOf: matchPattern(#"/?\s*>"#, in: text, type: .tag))
        tokens.append(contentsOf: matchPattern(#"\s[a-zA-Z-]+="#, in: text, type: .attribute))
        tokens.append(contentsOf: matchPattern(#""[^"]*""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'[^']*'"#, in: text, type: .string))
        return tokens
    }
    
    private func tokenizeCSS(_ text: String) -> [Token] {
        var tokens: [Token] = []
        tokens.append(contentsOf: matchPattern(#"/\*[\s\S]*?\*/"#, in: text, type: .comment))
        tokens.append(contentsOf: matchPattern(#"[.#]?[a-zA-Z][a-zA-Z0-9_-]*\s*\{"#, in: text, type: .type))
        tokens.append(contentsOf: matchPattern(#"[a-zA-Z-]+\s*:"#, in: text, type: .property))
        tokens.append(contentsOf: matchPattern(#"#[0-9a-fA-F]{3,8}\b"#, in: text, type: .number))
        tokens.append(contentsOf: matchPattern(#"\b\d+\.?\d*(px|em|rem|%|vh|vw|pt)?\b"#, in: text, type: .number))
        tokens.append(contentsOf: matchPattern(#""[^"]*""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'[^']*'"#, in: text, type: .string))
        return tokens
    }
    
    private func tokenizeJSON(_ text: String) -> [Token] {
        var tokens: [Token] = []
        tokens.append(contentsOf: matchPattern(#"\"[^\"\n]*\"\s*:"#, in: text, type: .property))
        tokens.append(contentsOf: matchPattern(#"\"[^\"\n]*\""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"-?\b\d+\.?\d*\b"#, in: text, type: .number))
        tokens.append(contentsOf: matchPattern(#"\b(true|false|null)\b"#, in: text, type: .keyword))
        return tokens
    }
    
    private func tokenizeYAML(_ text: String) -> [Token] {
        var tokens: [Token] = []
        tokens.append(contentsOf: matchPattern(#"#.*$"#, in: text, type: .comment))
        tokens.append(contentsOf: matchPattern(#"^[\s]*[a-zA-Z_][a-zA-Z0-9_]*:"#, in: text, type: .property))
        tokens.append(contentsOf: matchPattern(#""[^"]*""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'[^']*'"#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"\b\d+\.?\d*\b"#, in: text, type: .number))
        tokens.append(contentsOf: matchPattern(#"\b(true|false|yes|no|null|~)\b"#, in: text, type: .keyword))
        return tokens
    }
    
    private func tokenizeMarkdown(_ text: String) -> [Token] {
        var tokens: [Token] = []
        tokens.append(contentsOf: matchPattern(#"^#{1,6}\s+.+$"#, in: text, type: .heading))
        tokens.append(contentsOf: matchPattern(#"\*\*[^*\n]+\*\*"#, in: text, type: .emphasis))
        tokens.append(contentsOf: matchPattern(#"__[^_\n]+__"#, in: text, type: .emphasis))
        tokens.append(contentsOf: matchPattern(#"\*[^*\n]+\*"#, in: text, type: .emphasis))
        tokens.append(contentsOf: matchPattern(#"_[^_\n]+_"#, in: text, type: .emphasis))
        tokens.append(contentsOf: matchPattern(#"`[^`\n]+`"#, in: text, type: .codeBlock))
        tokens.append(contentsOf: matchPattern(#"\[[^\]]+\]\([^\)]+\)"#, in: text, type: .link))
        return tokens
    }
    
    private func matchPattern(_ pattern: String, in text: String, type: TokenType) -> [Token] {
        var tokens: [Token] = []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return tokens
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, options: [], range: range) {
            if let swiftRange = Range(match.range, in: text) {
                tokens.append(Token(range: swiftRange, type: type))
            }
        }
        return tokens
    }
    
    private func matchKeywords(_ keywords: Set<String>, in text: String) -> [Token] {
        var tokens: [Token] = []
        let pattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return tokens
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, options: [], range: range) {
            if let swiftRange = Range(match.range, in: text) {
                tokens.append(Token(range: swiftRange, type: .keyword))
            }
        }
        return tokens
    }
}

// MARK: - Screenshot Renderer

class ScreenshotRenderer {
    private let text: String
    private let fileType: SupportedFileType
    private let theme: SyntaxTheme
    private let includeLineNumbers: Bool
    private let fontSize: CGFloat
    private let fontName: String
    
    private let padding: CGFloat = 24
    private let lineNumberPadding: CGFloat = 12
    private let cornerRadius: CGFloat = 8
    
    init(text: String, fileType: SupportedFileType, theme: SyntaxTheme,
         includeLineNumbers: Bool = true, fontSize: CGFloat = 13, fontName: String = "Menlo") {
        self.text = text
        self.fileType = fileType
        self.theme = theme
        self.includeLineNumbers = includeLineNumbers
        self.fontSize = fontSize
        self.fontName = fontName
    }
    
    private func getFont() -> NSFont {
        return NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
    
    private func createAttributedContent() -> (lines: [(lineNum: NSAttributedString, code: NSAttributedString)], maxLineNumWidth: CGFloat) {
        let lines = text.components(separatedBy: "\n")
        let highlighter = SyntaxHighlighter(fileType: fileType, theme: theme)
        let font = getFont()
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        
        let lineCount = lines.count
        let maxDigits = String(lineCount).count
        
        // Calculate max line number width
        let sampleNum = String(repeating: "0", count: maxDigits)
        let sampleAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxLineNumWidth = (sampleNum as NSString).size(withAttributes: sampleAttrs).width
        
        var result: [(lineNum: NSAttributedString, code: NSAttributedString)] = []
        
        for (index, line) in lines.enumerated() {
            // Line number
            let lineNumStr = String(format: "%\(maxDigits)d", index + 1)
            let lineNumAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: theme.lineNumber,
                .paragraphStyle: paragraphStyle
            ]
            let lineNumAttr = NSAttributedString(string: lineNumStr, attributes: lineNumAttrs)
            
            // Code with syntax highlighting
            let codeAttr = NSMutableAttributedString()
            let tokens = highlighter.tokenize(line)
            
            if tokens.isEmpty || line.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: theme.plain,
                    .paragraphStyle: paragraphStyle
                ]
                codeAttr.append(NSAttributedString(string: line.isEmpty ? " " : line, attributes: attrs))
            } else {
                var lastEnd = line.startIndex
                
                for token in tokens.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
                    // Gap before token
                    if token.range.lowerBound > lastEnd {
                        let gap = String(line[lastEnd..<token.range.lowerBound])
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: theme.plain,
                            .paragraphStyle: paragraphStyle
                        ]
                        codeAttr.append(NSAttributedString(string: gap, attributes: attrs))
                    }
                    
                    // Token
                    let tokenText = String(line[token.range])
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: theme.color(for: token.type),
                        .paragraphStyle: paragraphStyle
                    ]
                    codeAttr.append(NSAttributedString(string: tokenText, attributes: attrs))
                    
                    lastEnd = token.range.upperBound
                }
                
                // Remainder
                if lastEnd < line.endIndex {
                    let remainder = String(line[lastEnd...])
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: theme.plain,
                        .paragraphStyle: paragraphStyle
                    ]
                    codeAttr.append(NSAttributedString(string: remainder, attributes: attrs))
                }
            }
            
            result.append((lineNumAttr, codeAttr))
        }
        
        return (result, maxLineNumWidth)
    }
    
    func exportToPNG(to url: URL) throws {
        let content = createAttributedContent()
        let font = getFont()
        let lineHeight = font.ascender - font.descender + font.leading + 4
        
        // Calculate dimensions
        let gutterWidth: CGFloat = includeLineNumbers ? content.maxLineNumWidth + lineNumberPadding * 2 : 0
        
        var maxCodeWidth: CGFloat = 0
        for (_, code) in content.lines {
            let size = code.size()
            maxCodeWidth = max(maxCodeWidth, size.width)
        }
        
        let totalWidth = gutterWidth + maxCodeWidth + padding * 2 + (includeLineNumbers ? lineNumberPadding : 0)
        let totalHeight = CGFloat(content.lines.count) * lineHeight + padding * 2
        
        // Create retina bitmap
        let scale: CGFloat = 2.0
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(totalWidth * scale),
            pixelsHigh: Int(totalHeight * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ExportError.renderFailed
        }
        
        bitmapRep.size = NSSize(width: totalWidth, height: totalHeight)
        
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            throw ExportError.renderFailed
        }
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        
        // Draw rounded background
        let bgPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: NSSize(width: totalWidth, height: totalHeight)),
                                   xRadius: cornerRadius, yRadius: cornerRadius)
        theme.background.setFill()
        bgPath.fill()
        
        // Draw gutter background
        if includeLineNumbers {
            let gutterRect = NSRect(x: 0, y: 0, width: gutterWidth, height: totalHeight)
            theme.gutterBackground.setFill()
            gutterRect.fill()
            
            // Draw separator
            theme.lineNumber.withAlphaComponent(0.3).setStroke()
            let separator = NSBezierPath()
            separator.move(to: NSPoint(x: gutterWidth, y: padding))
            separator.line(to: NSPoint(x: gutterWidth, y: totalHeight - padding))
            separator.lineWidth = 1
            separator.stroke()
        }
        
        // Draw each line
        var y = totalHeight - padding - font.ascender
        for (lineNum, code) in content.lines {
            if includeLineNumbers {
                // Draw line number (right-aligned in gutter)
                let lineNumSize = lineNum.size()
                let lineNumX = gutterWidth - lineNumSize.width - lineNumberPadding
                lineNum.draw(at: NSPoint(x: lineNumX, y: y))
            }
            
            // Draw code
            let codeX = gutterWidth + (includeLineNumbers ? lineNumberPadding : 0) + padding
            code.draw(at: NSPoint(x: codeX, y: y))
            
            y -= lineHeight
        }
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Save PNG
        guard let pngData = bitmapRep.representation(using: .png, properties: [.compressionFactor: 0.9]) else {
            throw ExportError.renderFailed
        }
        
        try pngData.write(to: url)
    }
    
    func exportToPDF(to url: URL) throws {
        let content = createAttributedContent()
        let font = getFont()
        let lineHeight = font.ascender - font.descender + font.leading + 4
        
        // Page dimensions
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let pageMargin: CGFloat = 36
        let contentWidth = pageWidth - pageMargin * 2
        let contentHeight = pageHeight - pageMargin * 2
        
        let gutterWidth: CGFloat = includeLineNumbers ? content.maxLineNumWidth + lineNumberPadding * 2 : 0
        let linesPerPage = Int(contentHeight / lineHeight)
        let totalPages = max(1, Int(ceil(Double(content.lines.count) / Double(linesPerPage))))
        
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.renderFailed
        }
        
        for pageIndex in 0..<totalPages {
            pdfContext.beginPDFPage(nil)
            
            // Fill background
            pdfContext.setFillColor(theme.background.cgColor)
            pdfContext.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            
            let nsContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext
            
            // Draw gutter
            if includeLineNumbers {
                theme.gutterBackground.setFill()
                NSRect(x: pageMargin, y: pageMargin, width: gutterWidth, height: contentHeight).fill()
                
                theme.lineNumber.withAlphaComponent(0.3).setStroke()
                let separator = NSBezierPath()
                separator.move(to: NSPoint(x: pageMargin + gutterWidth, y: pageMargin))
                separator.line(to: NSPoint(x: pageMargin + gutterWidth, y: pageHeight - pageMargin))
                separator.lineWidth = 0.5
                separator.stroke()
            }
            
            // Draw lines for this page
            let startLine = pageIndex * linesPerPage
            let endLine = min(startLine + linesPerPage, content.lines.count)
            
            var y = pageHeight - pageMargin - font.ascender
            for i in startLine..<endLine {
                let (lineNum, code) = content.lines[i]
                
                if includeLineNumbers {
                    let lineNumSize = lineNum.size()
                    let lineNumX = pageMargin + gutterWidth - lineNumSize.width - lineNumberPadding
                    lineNum.draw(at: NSPoint(x: lineNumX, y: y))
                }
                
                let codeX = pageMargin + gutterWidth + (includeLineNumbers ? lineNumberPadding : 0)
                code.draw(at: NSPoint(x: codeX, y: y))
                
                y -= lineHeight
            }
            
            NSGraphicsContext.restoreGraphicsState()
            pdfContext.endPDFPage()
        }
        
        pdfContext.closePDF()
        try (pdfData as Data).write(to: url)
    }
}

// MARK: - Errors

enum ExportError: Error, LocalizedError {
    case fileNotFound(String)
    case unsupportedFormat(String)
    case renderFailed
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .unsupportedFormat(let fmt): return "Unsupported format: \(fmt)"
        case .renderFailed: return "Failed to render document"
        }
    }
}

// MARK: - Main

func printUsage() {
    print("""
    qw-export - Render source code as PNG/PDF with syntax highlighting
    
    Usage: qw-export [options] <input-file>
    
    Options:
      -o, --output FILE      Output file path (default: input.png/pdf)
      -f, --format FORMAT    Output format: png, pdf (default: png)
      -t, --theme THEME      Theme: dark, light, monokai, dracula,
                             solarized-dark, solarized-light
      -s, --font-size SIZE   Font size in points (default: 13)
      --no-line-numbers      Hide line numbers
      -h, --help             Show this help
    
    Examples:
      qw-export sample.swift
      qw-export -f pdf --theme monokai sample.py -o output.pdf
      qw-export --no-line-numbers -t light sample.js
    """)
}

func getTheme(named name: String) -> SyntaxTheme {
    switch name.lowercased() {
    case "dark", "qw-dark": return .dark
    case "light", "qw-light": return .light
    case "monokai": return .monokai
    case "dracula": return .dracula
    case "solarized-dark", "solarized_dark": return .solarizedDark
    case "solarized-light", "solarized_light": return .solarizedLight
    default: return .dark
    }
}

// Parse arguments
var inputPath: String?
var outputPath: String?
var format = "png"
var themeName = "dark"
var lineNumbers = true
var fontSize: CGFloat = 13
var showHelp = false

var i = 1
while i < CommandLine.arguments.count {
    let arg = CommandLine.arguments[i]
    
    switch arg {
    case "-h", "--help":
        showHelp = true
    case "-o", "--output":
        i += 1
        if i < CommandLine.arguments.count { outputPath = CommandLine.arguments[i] }
    case "-f", "--format":
        i += 1
        if i < CommandLine.arguments.count { format = CommandLine.arguments[i].lowercased() }
    case "-t", "--theme":
        i += 1
        if i < CommandLine.arguments.count { themeName = CommandLine.arguments[i] }
    case "-s", "--font-size":
        i += 1
        if i < CommandLine.arguments.count, let s = Double(CommandLine.arguments[i]) { fontSize = CGFloat(s) }
    case "--no-line-numbers":
        lineNumbers = false
    default:
        if !arg.hasPrefix("-") && inputPath == nil { inputPath = arg }
    }
    i += 1
}

if showHelp {
    printUsage()
    exit(0)
}

guard let input = inputPath else {
    fputs("Error: No input file specified\n", stderr)
    printUsage()
    exit(1)
}

guard FileManager.default.fileExists(atPath: input) else {
    fputs("Error: File not found: \(input)\n", stderr)
    exit(1)
}

// Generate output path if not specified
let inputURL = URL(fileURLWithPath: input)
let output = outputPath ?? {
    let baseName = inputURL.deletingPathExtension().lastPathComponent
    let dir = inputURL.deletingLastPathComponent().path
    return "\(dir)/\(baseName).\(format)"
}()

// Read and export
do {
    let text = try String(contentsOfFile: input, encoding: .utf8)
    let fileType = SupportedFileType.from(url: inputURL)
    let theme = getTheme(named: themeName)
    
    let renderer = ScreenshotRenderer(
        text: text,
        fileType: fileType,
        theme: theme,
        includeLineNumbers: lineNumbers,
        fontSize: fontSize
    )
    
    let outputURL = URL(fileURLWithPath: output)
    
    switch format {
    case "png":
        try renderer.exportToPNG(to: outputURL)
    case "pdf":
        try renderer.exportToPDF(to: outputURL)
    default:
        fputs("Error: Unsupported format '\(format)'. Use 'png' or 'pdf'.\n", stderr)
        exit(1)
    }
    
    print("Exported to: \(output)")
    exit(0)
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
