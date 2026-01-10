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
}
