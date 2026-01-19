//
//  SyntaxHighlighterTests.swift
//  qwTests
//
//  Unit tests for SyntaxHighlighter
//

import XCTest
import SwiftUI
@testable import qw

final class SyntaxHighlighterTests: XCTestCase {
    
    // MARK: - Theme Tests
    
    func testLightThemeColors() {
        let theme = SyntaxTheme.light
        XCTAssertNotNil(theme.plain)
        XCTAssertNotNil(theme.keyword)
        XCTAssertNotNil(theme.string)
        XCTAssertNotNil(theme.comment)
        XCTAssertNotNil(theme.number)
        XCTAssertNotNil(theme.background)
    }
    
    func testDarkThemeColors() {
        let theme = SyntaxTheme.dark
        XCTAssertNotNil(theme.plain)
        XCTAssertNotNil(theme.keyword)
        XCTAssertNotNil(theme.string)
        XCTAssertNotNil(theme.comment)
        XCTAssertNotNil(theme.number)
        XCTAssertNotNil(theme.background)
    }
    
    func testThemeColorForTokenType() {
        let theme = SyntaxTheme.light
        
        // All token types should return a valid color
        XCTAssertNotNil(theme.color(for: .plain))
        XCTAssertNotNil(theme.color(for: .keyword))
        XCTAssertNotNil(theme.color(for: .string))
        XCTAssertNotNil(theme.color(for: .number))
        XCTAssertNotNil(theme.color(for: .comment))
    }
    
    // MARK: - Token Type Tests
    
    func testAllTokenTypesExist() {
        // Verify all token types are valid
        let tokenTypes: [TokenType] = [
            .plain, .keyword, .string, .number, .comment,
            .function, .type, .property, .tag, .attribute,
            .punctuation, .heading, .link, .emphasis, .codeBlock
        ]
        
        XCTAssertEqual(tokenTypes.count, 15)
    }

    private func rangesOverlap(_ lhs: Range<String.Index>, _ rhs: Range<String.Index>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    func testCommentShouldNotContainStringTokens_JavaScript() {
        let text = "// \"string inside comment\""
        let highlighter = SyntaxHighlighter(fileType: .javascript, theme: .dark)
        let tokens = highlighter.tokenize(text)

        let commentRanges = tokens.filter { $0.type == .comment }.map { $0.range }
        let stringRanges = tokens.filter { $0.type == .string }.map { $0.range }

        let hasOverlap = commentRanges.contains { commentRange in
            stringRanges.contains { rangesOverlap(commentRange, $0) }
        }

        XCTExpectFailure("Issue #17: Token ranges overlap (string tokens inside comments)")
        XCTAssertFalse(hasOverlap)
    }

    func testCommentShouldNotContainStringTokens_Python() {
        let text = "# 'string inside comment'"
        let highlighter = SyntaxHighlighter(fileType: .python, theme: .dark)
        let tokens = highlighter.tokenize(text)

        let commentRanges = tokens.filter { $0.type == .comment }.map { $0.range }
        let stringRanges = tokens.filter { $0.type == .string }.map { $0.range }

        let hasOverlap = commentRanges.contains { commentRange in
            stringRanges.contains { rangesOverlap(commentRange, $0) }
        }

        XCTExpectFailure("Issue #17: Token ranges overlap (string tokens inside comments)")
        XCTAssertFalse(hasOverlap)
    }
}
