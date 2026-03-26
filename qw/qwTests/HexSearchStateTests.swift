//
//  HexSearchStateTests.swift
//  qwTests
//
//  Tests for HexSearchState: hex pattern parsing, pattern bytes, match finding, and navigation.
//

import XCTest

#if os(macOS)
@testable import qw

final class HexSearchStateTests: XCTestCase {

    // MARK: - parseHexPattern

    func testParseHexPatternSpaceSeparated() {
        let state = HexSearchSession()
        let result = state.parseHexPattern("FF D8 FF")
        XCTAssertEqual(result, [0xFF, 0xD8, 0xFF])
    }

    func testParseHexPatternContiguousLowercase() {
        let state = HexSearchSession()
        let result = state.parseHexPattern("ffd8ff")
        XCTAssertEqual(result, [0xFF, 0xD8, 0xFF])
    }

    func testParseHexPatternSingleByte() {
        let state = HexSearchSession()
        let result = state.parseHexPattern("00")
        XCTAssertEqual(result, [0x00])
    }

    func testParseHexPatternEmptyReturnsNil() {
        let state = HexSearchSession()
        let result = state.parseHexPattern("")
        XCTAssertNil(result)
    }

    func testParseHexPatternOddLengthReturnsNil() {
        let state = HexSearchSession()
        let result = state.parseHexPattern("F")
        XCTAssertNil(result)
    }

    func testParseHexPatternNonHexReturnsNil() {
        let state = HexSearchSession()
        let result = state.parseHexPattern("GG")
        XCTAssertNil(result)
    }

    func testParseHexPatternOddAfterStrippingSpacesReturnsNil() {
        let state = HexSearchSession()
        let result = state.parseHexPattern("FF D8 F")
        XCTAssertNil(result)
    }

    // MARK: - patternBytes

    func testPatternBytesHexMode() {
        var state = HexSearchSession()
        state.searchMode = .hexPattern
        state.searchText = "FF00"
        let result = state.patternBytes()
        XCTAssertEqual(result, [0xFF, 0x00])
    }

    func testPatternBytesAsciiMode() {
        var state = HexSearchSession()
        state.searchMode = .asciiString
        state.searchText = "abc"
        let result = state.patternBytes()
        XCTAssertEqual(result, [0x61, 0x62, 0x63])
    }

    // MARK: - findMatches

    func testFindMatchesEmptySearchText() {
        var state = HexSearchSession()
        state.searchText = ""
        state.findMatches(in: Data([0x01, 0x02, 0x03]))
        XCTAssertTrue(state.matches.isEmpty)
        XCTAssertEqual(state.currentMatchIndex, 0)
    }

    func testFindMatchesPatternNotFound() {
        var state = HexSearchSession()
        state.searchMode = .hexPattern
        state.searchText = "DEAD"
        state.findMatches(in: Data([0x01, 0x02, 0x03, 0x04]))
        XCTAssertTrue(state.matches.isEmpty)
    }

    func testFindMatchesSingleMatch() {
        var state = HexSearchSession()
        state.searchMode = .hexPattern
        state.searchText = "0203"
        let data = Data([0x01, 0x02, 0x03, 0x04])
        state.findMatches(in: data)
        XCTAssertEqual(state.matches.count, 1)
        XCTAssertEqual(state.matches.first, 1..<3)
    }

    func testFindMatchesMultipleNonOverlapping() {
        var state = HexSearchSession()
        state.searchMode = .hexPattern
        state.searchText = "FF"
        let data = Data([0xFF, 0x00, 0xFF, 0x00, 0xFF])
        state.findMatches(in: data)
        XCTAssertEqual(state.matches.count, 3)
        XCTAssertEqual(state.matches[0], 0..<1)
        XCTAssertEqual(state.matches[1], 2..<3)
        XCTAssertEqual(state.matches[2], 4..<5)
    }

    func testFindMatchesNonOverlappingRepeatedPattern() {
        // "AAAA" (2 bytes: 0xAA, 0xAA) in 3 bytes: AA AA AA
        // Non-overlapping: match at 0, skip to 2, only 1 byte left → 1 match
        var state = HexSearchSession()
        state.searchMode = .hexPattern
        state.searchText = "AAAA"
        let data = Data([0xAA, 0xAA, 0xAA])
        state.findMatches(in: data)
        XCTAssertEqual(state.matches.count, 1)
        XCTAssertEqual(state.matches.first, 0..<2)
    }

    func testFindMatchesAsciiMode() {
        var state = HexSearchSession()
        state.searchMode = .asciiString
        state.searchText = "hello"
        let str = "hello world hello"
        let data = Data(str.utf8)
        state.findMatches(in: data)
        XCTAssertEqual(state.matches.count, 2)
        XCTAssertEqual(state.matches[0], 0..<5)
        XCTAssertEqual(state.matches[1], 12..<17)
    }

    // MARK: - Navigation

    func testFindNextWrapsAround() {
        var state = HexSearchSession()
        state.searchMode = .hexPattern
        state.searchText = "FF"
        let data = Data([0xFF, 0x00, 0xFF])
        state.findMatches(in: data)
        XCTAssertEqual(state.matches.count, 2)
        XCTAssertEqual(state.currentMatchIndex, 0)

        state.findNext() // → 1
        XCTAssertEqual(state.currentMatchIndex, 1)

        state.findNext() // wraps → 0
        XCTAssertEqual(state.currentMatchIndex, 0)
    }

    func testFindPreviousWrapsAround() {
        var state = HexSearchSession()
        state.searchMode = .hexPattern
        state.searchText = "FF"
        let data = Data([0xFF, 0x00, 0xFF])
        state.findMatches(in: data)
        XCTAssertEqual(state.matches.count, 2)
        XCTAssertEqual(state.currentMatchIndex, 0)

        state.findPrevious() // wraps → 1
        XCTAssertEqual(state.currentMatchIndex, 1)

        state.findPrevious() // → 0
        XCTAssertEqual(state.currentMatchIndex, 0)
    }

    func testFindNextOnEmptyMatchesDoesNothing() {
        var state = HexSearchSession()
        XCTAssertTrue(state.matches.isEmpty)
        state.findNext()
        XCTAssertEqual(state.currentMatchIndex, 0)
    }

    func testFindPreviousOnEmptyMatchesDoesNothing() {
        var state = HexSearchSession()
        XCTAssertTrue(state.matches.isEmpty)
        state.findPrevious()
        XCTAssertEqual(state.currentMatchIndex, 0)
    }
}

#endif
