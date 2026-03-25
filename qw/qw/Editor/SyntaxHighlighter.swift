//
//  SyntaxHighlighter.swift
//  qw
//
//  Syntax highlighting engine for QW editor
//

import SwiftUI
import PygmentsSwift

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
    
    // Solarized Light
    static let solarizedLight = SyntaxTheme(
        plain: Color(red: 0.396, green: 0.482, blue: 0.514),
        keyword: Color(red: 0.149, green: 0.545, blue: 0.824),
        string: Color(red: 0.165, green: 0.631, blue: 0.596),
        number: Color(red: 0.827, green: 0.212, blue: 0.510),
        comment: Color(red: 0.576, green: 0.631, blue: 0.631),
        function: Color(red: 0.149, green: 0.545, blue: 0.824),
        type: Color(red: 0.710, green: 0.537, blue: 0.000),
        property: Color(red: 0.396, green: 0.482, blue: 0.514),
        tag: Color(red: 0.827, green: 0.212, blue: 0.510),
        attribute: Color(red: 0.710, green: 0.537, blue: 0.000),
        punctuation: Color(red: 0.396, green: 0.482, blue: 0.514),
        heading: Color(red: 0.522, green: 0.600, blue: 0.000),
        link: Color(red: 0.149, green: 0.545, blue: 0.824),
        emphasis: Color(red: 0.827, green: 0.212, blue: 0.510),
        codeBlock: Color(red: 0.576, green: 0.631, blue: 0.631),
        background: Color(red: 0.992, green: 0.965, blue: 0.890),
        lineNumber: Color(red: 0.576, green: 0.631, blue: 0.631),
        selection: Color(red: 0.933, green: 0.910, blue: 0.835)
    )
    
    // Solarized Dark
    static let solarizedDark = SyntaxTheme(
        plain: Color(red: 0.514, green: 0.580, blue: 0.588),
        keyword: Color(red: 0.149, green: 0.545, blue: 0.824),
        string: Color(red: 0.165, green: 0.631, blue: 0.596),
        number: Color(red: 0.827, green: 0.212, blue: 0.510),
        comment: Color(red: 0.396, green: 0.482, blue: 0.514),
        function: Color(red: 0.149, green: 0.545, blue: 0.824),
        type: Color(red: 0.710, green: 0.537, blue: 0.000),
        property: Color(red: 0.514, green: 0.580, blue: 0.588),
        tag: Color(red: 0.827, green: 0.212, blue: 0.510),
        attribute: Color(red: 0.710, green: 0.537, blue: 0.000),
        punctuation: Color(red: 0.514, green: 0.580, blue: 0.588),
        heading: Color(red: 0.522, green: 0.600, blue: 0.000),
        link: Color(red: 0.149, green: 0.545, blue: 0.824),
        emphasis: Color(red: 0.827, green: 0.212, blue: 0.510),
        codeBlock: Color(red: 0.396, green: 0.482, blue: 0.514),
        background: Color(red: 0.000, green: 0.169, blue: 0.212),
        lineNumber: Color(red: 0.396, green: 0.482, blue: 0.514),
        selection: Color(red: 0.027, green: 0.212, blue: 0.259)
    )
    
    // Monokai
    static let monokai = SyntaxTheme(
        plain: Color(red: 0.973, green: 0.973, blue: 0.949),
        keyword: Color(red: 0.984, green: 0.149, blue: 0.447),
        string: Color(red: 0.902, green: 0.859, blue: 0.455),
        number: Color(red: 0.682, green: 0.506, blue: 1.000),
        comment: Color(red: 0.467, green: 0.451, blue: 0.404),
        function: Color(red: 0.400, green: 0.851, blue: 0.937),
        type: Color(red: 0.400, green: 0.851, blue: 0.937),
        property: Color(red: 0.973, green: 0.973, blue: 0.949),
        tag: Color(red: 0.984, green: 0.149, blue: 0.447),
        attribute: Color(red: 0.651, green: 0.886, blue: 0.180),
        punctuation: Color(red: 0.973, green: 0.973, blue: 0.949),
        heading: Color(red: 0.682, green: 0.506, blue: 1.000),
        link: Color(red: 0.400, green: 0.851, blue: 0.937),
        emphasis: Color(red: 0.984, green: 0.149, blue: 0.447),
        codeBlock: Color(red: 0.467, green: 0.451, blue: 0.404),
        background: Color(red: 0.153, green: 0.157, blue: 0.133),
        lineNumber: Color(red: 0.467, green: 0.451, blue: 0.404),
        selection: Color(red: 0.286, green: 0.286, blue: 0.259)
    )
    
    // Dracula
    static let dracula = SyntaxTheme(
        plain: Color(red: 0.973, green: 0.973, blue: 0.949),
        keyword: Color(red: 1.000, green: 0.475, blue: 0.776),
        string: Color(red: 0.945, green: 0.980, blue: 0.549),
        number: Color(red: 0.741, green: 0.576, blue: 0.976),
        comment: Color(red: 0.384, green: 0.447, blue: 0.643),
        function: Color(red: 0.314, green: 0.980, blue: 0.482),
        type: Color(red: 0.545, green: 0.914, blue: 0.992),
        property: Color(red: 0.973, green: 0.973, blue: 0.949),
        tag: Color(red: 1.000, green: 0.475, blue: 0.776),
        attribute: Color(red: 0.314, green: 0.980, blue: 0.482),
        punctuation: Color(red: 0.973, green: 0.973, blue: 0.949),
        heading: Color(red: 0.741, green: 0.576, blue: 0.976),
        link: Color(red: 0.545, green: 0.914, blue: 0.992),
        emphasis: Color(red: 1.000, green: 0.475, blue: 0.776),
        codeBlock: Color(red: 0.384, green: 0.447, blue: 0.643),
        background: Color(red: 0.157, green: 0.165, blue: 0.212),
        lineNumber: Color(red: 0.384, green: 0.447, blue: 0.643),
        selection: Color(red: 0.263, green: 0.278, blue: 0.353)
    )
    
    // Nord
    static let nord = SyntaxTheme(
        plain: Color(red: 0.847, green: 0.871, blue: 0.914),
        keyword: Color(red: 0.506, green: 0.631, blue: 0.757),
        string: Color(red: 0.651, green: 0.741, blue: 0.451),
        number: Color(red: 0.706, green: 0.557, blue: 0.678),
        comment: Color(red: 0.396, green: 0.455, blue: 0.525),
        function: Color(red: 0.533, green: 0.753, blue: 0.816),
        type: Color(red: 0.533, green: 0.753, blue: 0.816),
        property: Color(red: 0.847, green: 0.871, blue: 0.914),
        tag: Color(red: 0.506, green: 0.631, blue: 0.757),
        attribute: Color(red: 0.651, green: 0.741, blue: 0.451),
        punctuation: Color(red: 0.847, green: 0.871, blue: 0.914),
        heading: Color(red: 0.533, green: 0.753, blue: 0.816),
        link: Color(red: 0.533, green: 0.753, blue: 0.816),
        emphasis: Color(red: 0.706, green: 0.557, blue: 0.678),
        codeBlock: Color(red: 0.396, green: 0.455, blue: 0.525),
        background: Color(red: 0.180, green: 0.204, blue: 0.251),
        lineNumber: Color(red: 0.396, green: 0.455, blue: 0.525),
        selection: Color(red: 0.263, green: 0.298, blue: 0.369)
    )
    
    // One Dark
    static let oneDark = SyntaxTheme(
        plain: Color(red: 0.671, green: 0.706, blue: 0.757),
        keyword: Color(red: 0.780, green: 0.475, blue: 0.765),
        string: Color(red: 0.596, green: 0.765, blue: 0.478),
        number: Color(red: 0.824, green: 0.529, blue: 0.373),
        comment: Color(red: 0.373, green: 0.404, blue: 0.455),
        function: Color(red: 0.380, green: 0.706, blue: 0.922),
        type: Color(red: 0.902, green: 0.765, blue: 0.459),
        property: Color(red: 0.902, green: 0.439, blue: 0.451),
        tag: Color(red: 0.902, green: 0.439, blue: 0.451),
        attribute: Color(red: 0.824, green: 0.529, blue: 0.373),
        punctuation: Color(red: 0.671, green: 0.706, blue: 0.757),
        heading: Color(red: 0.902, green: 0.439, blue: 0.451),
        link: Color(red: 0.380, green: 0.706, blue: 0.922),
        emphasis: Color(red: 0.780, green: 0.475, blue: 0.765),
        codeBlock: Color(red: 0.373, green: 0.404, blue: 0.455),
        background: Color(red: 0.157, green: 0.173, blue: 0.204),
        lineNumber: Color(red: 0.373, green: 0.404, blue: 0.455),
        selection: Color(red: 0.243, green: 0.267, blue: 0.318)
    )
    
    // GitHub
    static let github = SyntaxTheme(
        plain: Color(red: 0.149, green: 0.196, blue: 0.220),
        keyword: Color(red: 0.839, green: 0.227, blue: 0.361),
        string: Color(red: 0.110, green: 0.384, blue: 0.620),
        number: Color(red: 0.004, green: 0.506, blue: 0.302),
        comment: Color(red: 0.420, green: 0.478, blue: 0.533),
        function: Color(red: 0.435, green: 0.259, blue: 0.757),
        type: Color(red: 0.839, green: 0.227, blue: 0.361),
        property: Color(red: 0.004, green: 0.506, blue: 0.302),
        tag: Color(red: 0.137, green: 0.427, blue: 0.298),
        attribute: Color(red: 0.435, green: 0.259, blue: 0.757),
        punctuation: Color(red: 0.149, green: 0.196, blue: 0.220),
        heading: Color(red: 0.110, green: 0.384, blue: 0.620),
        link: Color(red: 0.110, green: 0.384, blue: 0.620),
        emphasis: Color(red: 0.839, green: 0.227, blue: 0.361),
        codeBlock: Color(red: 0.420, green: 0.478, blue: 0.533),
        background: Color(red: 1.000, green: 1.000, blue: 1.000),
        lineNumber: Color(red: 0.420, green: 0.478, blue: 0.533),
        selection: Color(red: 0.886, green: 0.941, blue: 1.000)
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

/// Main syntax highlighter (PygmentsSwift-backed)
class SyntaxHighlighter {
    let fileType: SupportedFileType
    let theme: SyntaxTheme
    let fileName: String?

    init(fileType: SupportedFileType, theme: SyntaxTheme, fileName: String? = nil) {
        self.fileType = fileType
        self.theme = theme
        self.fileName = fileName
    }

    /// Highlight text and return attributed string
    func highlight(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
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

    /// Tokenize text using PygmentsSwift
    func tokenize(_ text: String) -> [Token] {
        guard let lexer = makeLexer() else { return [] }
        let pygmentsTokens = lexer.getTokens(text)
        if pygmentsTokens.isEmpty { return [] }

        let totalLength = text.utf16.count

        let allTokens: [Token] = pygmentsTokens.compactMap { token in
            let length = token.value.utf16.count
            guard length > 0 else { return nil }
            let end = token.start + length
            guard token.start >= 0, end <= totalLength else { return nil }
            let nsRange = NSRange(location: token.start, length: length)
            guard let range = Range(nsRange, in: text) else { return nil }
            return Token(range: range, type: mapTokenType(token.type))
        }

        // Collect comment ranges so we can suppress tokens that overlap them
        let commentRanges = allTokens.filter { $0.type == .comment }.map { $0.range }

        return allTokens.filter { token in
            if token.type == .comment { return true }
            // Drop non-comment tokens whose range overlaps any comment range
            return !commentRanges.contains { commentRange in
                token.range.lowerBound < commentRange.upperBound &&
                commentRange.lowerBound < token.range.upperBound
            }
        }
    }

    private func makeLexer() -> PygmentsSwift.Lexer? {
        if let fileName, let lexer = PygmentsSwift.LexerRegistry.makeLexer(filename: fileName) {
            return lexer
        }

        if let languageName = languageNameForFileType(),
           let lexer = PygmentsSwift.LexerRegistry.makeLexer(languageName: languageName) {
            return lexer
        }

        let fallbackName = "file.\(fileType.rawValue)"
        return PygmentsSwift.LexerRegistry.makeLexer(filename: fallbackName)
    }

    private func languageNameForFileType() -> String? {
        switch fileType {
        case .plainText:
            return nil
        case .markdown:
            return "markdown"
        case .json:
            return "json"
        case .yaml, .yml:
            return "yaml"
        case .python:
            return "python"
        case .javascript:
            return "javascript"
        case .html:
            return "html"
        case .css:
            return "css"
        case .swift:
            return "swift"
        }
    }

    private func mapTokenType(_ type: PygmentsSwift.TokenType) -> TokenType {
        if type.isSubtype(of: .comment) { return .comment }
        if type.isSubtype(of: .string) { return .string }
        if type.isSubtype(of: .number) { return .number }
        if type.isSubtype(of: .keyword) { return .keyword }

        if type.isSubtype(of: .name.child("Function")) { return .function }
        if type.isSubtype(of: .name.child("Class")) { return .type }
        if type.isSubtype(of: .keyword.child("Type")) { return .type }

        if type.isSubtype(of: .name.child("Attribute")) { return .attribute }
        if type.isSubtype(of: .name.child("Tag")) { return .tag }
        if type.isSubtype(of: .name.child("Decorator")) { return .attribute }

        if type.isSubtype(of: .name.child("Variable")) { return .property }
        if type.isSubtype(of: .name.child("Property")) { return .property }
        if type.isSubtype(of: .name.child("Builtin")) { return .property }
        if type.isSubtype(of: .name) { return .property }

        if type.isSubtype(of: .punctuation) { return .punctuation }
        if type.isSubtype(of: .operator) { return .punctuation }

        if type.isSubtype(of: .text) { return .plain }
        if type.isSubtype(of: .whitespace) { return .plain }

        return .plain
    }
}
