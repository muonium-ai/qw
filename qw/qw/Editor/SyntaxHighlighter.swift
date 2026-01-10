//
//  SyntaxHighlighter.swift
//  qw
//
//  Syntax highlighting engine for QW editor
//

import SwiftUI

/// Token types for syntax highlighting
enum TokenType {
    case plain
    case keyword
    case string
    case number
    case comment
    case function
    case type
    case property
    case tag
    case attribute
    case punctuation
    case heading
    case link
    case emphasis
    case codeBlock
}

/// A token with its range and type
struct Token {
    let range: Range<String.Index>
    let type: TokenType
}

/// Theme colors for syntax highlighting
struct SyntaxTheme {
    let plain: Color
    let keyword: Color
    let string: Color
    let number: Color
    let comment: Color
    let function: Color
    let type: Color
    let property: Color
    let tag: Color
    let attribute: Color
    let punctuation: Color
    let heading: Color
    let link: Color
    let emphasis: Color
    let codeBlock: Color
    let background: Color
    let lineNumber: Color
    let selection: Color
    
    static let light = SyntaxTheme(
        plain: Color(red: 0.1, green: 0.1, blue: 0.1),
        keyword: Color(red: 0.6, green: 0.2, blue: 0.6),
        string: Color(red: 0.7, green: 0.1, blue: 0.1),
        number: Color(red: 0.1, green: 0.4, blue: 0.7),
        comment: Color(red: 0.4, green: 0.5, blue: 0.4),
        function: Color(red: 0.2, green: 0.4, blue: 0.6),
        type: Color(red: 0.4, green: 0.3, blue: 0.6),
        property: Color(red: 0.3, green: 0.4, blue: 0.5),
        tag: Color(red: 0.6, green: 0.2, blue: 0.2),
        attribute: Color(red: 0.5, green: 0.3, blue: 0.1),
        punctuation: Color(red: 0.3, green: 0.3, blue: 0.3),
        heading: Color(red: 0.1, green: 0.3, blue: 0.6),
        link: Color(red: 0.1, green: 0.4, blue: 0.8),
        emphasis: Color(red: 0.4, green: 0.2, blue: 0.4),
        codeBlock: Color(red: 0.3, green: 0.3, blue: 0.3),
        background: Color(red: 1.0, green: 1.0, blue: 1.0),
        lineNumber: Color(red: 0.6, green: 0.6, blue: 0.6),
        selection: Color(red: 0.8, green: 0.9, blue: 1.0)
    )
    
    static let dark = SyntaxTheme(
        plain: Color(red: 0.9, green: 0.9, blue: 0.9),
        keyword: Color(red: 0.9, green: 0.5, blue: 0.8),
        string: Color(red: 0.9, green: 0.6, blue: 0.5),
        number: Color(red: 0.6, green: 0.8, blue: 0.9),
        comment: Color(red: 0.5, green: 0.6, blue: 0.5),
        function: Color(red: 0.5, green: 0.7, blue: 0.9),
        type: Color(red: 0.7, green: 0.6, blue: 0.9),
        property: Color(red: 0.6, green: 0.7, blue: 0.8),
        tag: Color(red: 0.9, green: 0.5, blue: 0.5),
        attribute: Color(red: 0.9, green: 0.7, blue: 0.5),
        punctuation: Color(red: 0.7, green: 0.7, blue: 0.7),
        heading: Color(red: 0.5, green: 0.7, blue: 0.9),
        link: Color(red: 0.5, green: 0.7, blue: 1.0),
        emphasis: Color(red: 0.8, green: 0.6, blue: 0.8),
        codeBlock: Color(red: 0.7, green: 0.7, blue: 0.7),
        background: Color(red: 0.12, green: 0.12, blue: 0.14),
        lineNumber: Color(red: 0.5, green: 0.5, blue: 0.5),
        selection: Color(red: 0.2, green: 0.3, blue: 0.4)
    )
    
    func color(for tokenType: TokenType) -> Color {
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

/// Main syntax highlighter
class SyntaxHighlighter {
    let fileType: SupportedFileType
    let theme: SyntaxTheme
    
    // Language keywords
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
    
    private static let htmlTags = Set([
        "html", "head", "body", "div", "span", "p", "a", "img", "ul", "ol", "li",
        "table", "tr", "td", "th", "form", "input", "button", "select", "option",
        "textarea", "label", "script", "style", "link", "meta", "title", "header",
        "footer", "nav", "main", "section", "article", "aside", "h1", "h2", "h3",
        "h4", "h5", "h6", "br", "hr", "pre", "code", "blockquote", "strong", "em"
    ])
    
    init(fileType: SupportedFileType, theme: SyntaxTheme) {
        self.fileType = fileType
        self.theme = theme
    }
    
    /// Highlight text and return attributed string
    func highlight(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        // Set base attributes
        attributedString.foregroundColor = theme.plain
        
        let tokens = tokenize(text)
        
        for token in tokens {
            if let range = Range(token.range, in: attributedString) {
                attributedString[range].foregroundColor = theme.color(for: token.type)
                
                // Add bold for keywords and headings
                if token.type == .keyword || token.type == .heading {
                    attributedString[range].font = .system(.body, weight: .semibold)
                }
                
                // Add italic for comments and emphasis
                if token.type == .comment || token.type == .emphasis {
                    attributedString[range].font = .system(.body).italic()
                }
            }
        }
        
        return attributedString
    }
    
    /// Tokenize text based on file type (public for direct use)
    func tokenize(_ text: String) -> [Token] {
        switch fileType {
        case .python:
            return tokenizePython(text)
        case .javascript:
            return tokenizeJavaScript(text)
        case .swift:
            return tokenizeSwift(text)
        case .html:
            return tokenizeHTML(text)
        case .css:
            return tokenizeCSS(text)
        case .json:
            return tokenizeJSON(text)
        case .yaml, .yml:
            return tokenizeYAML(text)
        case .markdown:
            return tokenizeMarkdown(text)
        case .plainText:
            return []
        }
    }
    
    // MARK: - Python Tokenizer
    private func tokenizePython(_ text: String) -> [Token] {
        var tokens: [Token] = []
        
        // Comments
        tokens.append(contentsOf: matchPattern(#"#.*$"#, in: text, type: .comment))
        
        // Strings (triple quotes and single/double)
        tokens.append(contentsOf: matchPattern(#"\"\"\"[\s\S]*?\"\"\""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'''[\s\S]*?'''"#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#""[^"\\]*(?:\\.[^"\\]*)*""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'[^'\\]*(?:\\.[^'\\]*)*'"#, in: text, type: .string))
        
        // Numbers
        tokens.append(contentsOf: matchPattern(#"\b\d+\.?\d*\b"#, in: text, type: .number))
        
        // Keywords
        tokens.append(contentsOf: matchKeywords(Self.pythonKeywords, in: text))
        
        // Function definitions
        tokens.append(contentsOf: matchPattern(#"(?<=def\s)\w+"#, in: text, type: .function))
        tokens.append(contentsOf: matchPattern(#"(?<=class\s)\w+"#, in: text, type: .type))
        
        return tokens
    }
    
    // MARK: - JavaScript Tokenizer
    private func tokenizeJavaScript(_ text: String) -> [Token] {
        var tokens: [Token] = []
        
        // Comments
        tokens.append(contentsOf: matchPattern(#"//.*$"#, in: text, type: .comment))
        tokens.append(contentsOf: matchPattern(#"/\*[\s\S]*?\*/"#, in: text, type: .comment))
        
        // Strings
        tokens.append(contentsOf: matchPattern(#"`[^`]*`"#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#""[^"\\]*(?:\\.[^"\\]*)*""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'[^'\\]*(?:\\.[^'\\]*)*'"#, in: text, type: .string))
        
        // Numbers
        tokens.append(contentsOf: matchPattern(#"\b\d+\.?\d*\b"#, in: text, type: .number))
        
        // Keywords
        tokens.append(contentsOf: matchKeywords(Self.javascriptKeywords, in: text))
        
        // Function names
        tokens.append(contentsOf: matchPattern(#"(?<=function\s)\w+"#, in: text, type: .function))
        
        return tokens
    }
    
    // MARK: - Swift Tokenizer
    private func tokenizeSwift(_ text: String) -> [Token] {
        var tokens: [Token] = []
        
        // Comments
        tokens.append(contentsOf: matchPattern(#"//.*$"#, in: text, type: .comment))
        tokens.append(contentsOf: matchPattern(#"/\*[\s\S]*?\*/"#, in: text, type: .comment))
        
        // Strings
        tokens.append(contentsOf: matchPattern(#"\"\"\"[\s\S]*?\"\"\""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#""[^"\\]*(?:\\.[^"\\]*)*""#, in: text, type: .string))
        
        // Numbers
        tokens.append(contentsOf: matchPattern(#"\b\d+\.?\d*\b"#, in: text, type: .number))
        
        // Keywords
        tokens.append(contentsOf: matchKeywords(Self.swiftKeywords, in: text))
        
        // Types (capitalized words)
        tokens.append(contentsOf: matchPattern(#"\b[A-Z][a-zA-Z0-9]*\b"#, in: text, type: .type))
        
        // Function definitions
        tokens.append(contentsOf: matchPattern(#"(?<=func\s)\w+"#, in: text, type: .function))
        
        return tokens
    }
    
    // MARK: - HTML Tokenizer
    private func tokenizeHTML(_ text: String) -> [Token] {
        var tokens: [Token] = []
        
        // Comments
        tokens.append(contentsOf: matchPattern(#"<!--[\s\S]*?-->"#, in: text, type: .comment))
        
        // Tags
        tokens.append(contentsOf: matchPattern(#"</?[a-zA-Z][a-zA-Z0-9]*"#, in: text, type: .tag))
        tokens.append(contentsOf: matchPattern(#"/?\s*>"#, in: text, type: .tag))
        
        // Attributes
        tokens.append(contentsOf: matchPattern(#"\s[a-zA-Z-]+(?=\s*=)"#, in: text, type: .attribute))
        
        // Strings
        tokens.append(contentsOf: matchPattern(#""[^"]*""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'[^']*'"#, in: text, type: .string))
        
        return tokens
    }
    
    // MARK: - CSS Tokenizer
    private func tokenizeCSS(_ text: String) -> [Token] {
        var tokens: [Token] = []
        
        // Comments
        tokens.append(contentsOf: matchPattern(#"/\*[\s\S]*?\*/"#, in: text, type: .comment))
        
        // Selectors
        tokens.append(contentsOf: matchPattern(#"[.#]?[a-zA-Z][a-zA-Z0-9_-]*(?=\s*\{)"#, in: text, type: .type))
        
        // Properties
        tokens.append(contentsOf: matchPattern(#"[a-zA-Z-]+(?=\s*:)"#, in: text, type: .property))
        
        // Values
        tokens.append(contentsOf: matchPattern(#"#[0-9a-fA-F]{3,8}\b"#, in: text, type: .number))
        tokens.append(contentsOf: matchPattern(#"\b\d+\.?\d*(px|em|rem|%|vh|vw|pt)?\b"#, in: text, type: .number))
        
        // Strings
        tokens.append(contentsOf: matchPattern(#""[^"]*""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'[^']*'"#, in: text, type: .string))
        
        return tokens
    }
    
    // MARK: - JSON Tokenizer
    private func tokenizeJSON(_ text: String) -> [Token] {
        var tokens: [Token] = []
        
        // Property keys
        tokens.append(contentsOf: matchPattern(#""[^"]+"\s*(?=:)"#, in: text, type: .property))
        
        // String values
        tokens.append(contentsOf: matchPattern(#":\s*"[^"]*""#, in: text, type: .string))
        
        // Numbers
        tokens.append(contentsOf: matchPattern(#":\s*-?\d+\.?\d*"#, in: text, type: .number))
        
        // Booleans and null
        tokens.append(contentsOf: matchPattern(#"\b(true|false|null)\b"#, in: text, type: .keyword))
        
        // Punctuation
        tokens.append(contentsOf: matchPattern(#"[\{\}\[\],:]"#, in: text, type: .punctuation))
        
        return tokens
    }
    
    // MARK: - YAML Tokenizer
    private func tokenizeYAML(_ text: String) -> [Token] {
        var tokens: [Token] = []
        
        // Comments
        tokens.append(contentsOf: matchPattern(#"#.*$"#, in: text, type: .comment))
        
        // Keys
        tokens.append(contentsOf: matchPattern(#"^[\s-]*[a-zA-Z_][a-zA-Z0-9_]*(?=\s*:)"#, in: text, type: .property))
        
        // Strings
        tokens.append(contentsOf: matchPattern(#""[^"]*""#, in: text, type: .string))
        tokens.append(contentsOf: matchPattern(#"'[^']*'"#, in: text, type: .string))
        
        // Numbers
        tokens.append(contentsOf: matchPattern(#":\s*-?\d+\.?\d*\s*$"#, in: text, type: .number))
        
        // Booleans and null
        tokens.append(contentsOf: matchPattern(#"\b(true|false|yes|no|null|~)\b"#, in: text, type: .keyword))
        
        return tokens
    }
    
    // MARK: - Markdown Tokenizer
    private func tokenizeMarkdown(_ text: String) -> [Token] {
        var tokens: [Token] = []
        
        // Headings
        tokens.append(contentsOf: matchPattern(#"^#{1,6}\s+.+$"#, in: text, type: .heading))
        
        // Bold
        tokens.append(contentsOf: matchPattern(#"\*\*[^*]+\*\*"#, in: text, type: .emphasis))
        tokens.append(contentsOf: matchPattern(#"__[^_]+__"#, in: text, type: .emphasis))
        
        // Italic
        tokens.append(contentsOf: matchPattern(#"\*[^*]+\*"#, in: text, type: .emphasis))
        tokens.append(contentsOf: matchPattern(#"_[^_]+_"#, in: text, type: .emphasis))
        
        // Code blocks
        tokens.append(contentsOf: matchPattern(#"```[\s\S]*?```"#, in: text, type: .codeBlock))
        tokens.append(contentsOf: matchPattern(#"`[^`]+`"#, in: text, type: .codeBlock))
        
        // Links
        tokens.append(contentsOf: matchPattern(#"\[([^\]]+)\]\([^\)]+\)"#, in: text, type: .link))
        
        // Lists
        tokens.append(contentsOf: matchPattern(#"^[\s]*[-*+]\s"#, in: text, type: .punctuation))
        tokens.append(contentsOf: matchPattern(#"^[\s]*\d+\.\s"#, in: text, type: .punctuation))
        
        return tokens
    }
    
    // MARK: - Helper Methods
    
    private func matchPattern(_ pattern: String, in text: String, type: TokenType) -> [Token] {
        var tokens: [Token] = []
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return tokens
        }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
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
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            if let swiftRange = Range(match.range, in: text) {
                tokens.append(Token(range: swiftRange, type: .keyword))
            }
        }
        
        return tokens
    }
}
