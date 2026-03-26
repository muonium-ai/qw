//
//  HexSearchState.swift
//  qw
//
//  Search/replace state for hex mode — searches for hex byte patterns or ASCII strings.
//  Ticket: T-000022
//

import Combine
import Foundation
import SwiftUI

/// How the search query should be interpreted.
enum HexSearchMode: String, CaseIterable, Identifiable {
    case hexPattern = "Hex"
    case asciiString = "ASCII"

    var id: String { rawValue }
}

/// Pure search state shared by HexSearchState and tests.
struct HexSearchSession {
    var searchText: String = ""
    var replaceText: String = ""
    var searchMode: HexSearchMode = .hexPattern
    var matches: [Range<Int>] = []
    var currentMatchIndex: Int = 0

    mutating func findMatches(in data: Data) {
        guard !searchText.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }

        guard let pattern = patternBytes(), !pattern.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }

        var results: [Range<Int>] = []
        var offset = 0
        let count = data.count
        let patternCount = pattern.count

        while offset + patternCount <= count {
            var found = true
            for i in 0..<patternCount {
                if data[data.startIndex + offset + i] != pattern[i] {
                    found = false
                    break
                }
            }
            if found {
                results.append(offset..<(offset + patternCount))
                offset += patternCount
            } else {
                offset += 1
            }
        }

        matches = results
        if matches.isEmpty {
            currentMatchIndex = 0
        } else if currentMatchIndex >= matches.count {
            currentMatchIndex = matches.count - 1
        }
    }

    mutating func findNext() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    mutating func findPrevious() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = currentMatchIndex > 0 ? currentMatchIndex - 1 : matches.count - 1
    }

    func patternBytes() -> [UInt8]? {
        switch searchMode {
        case .hexPattern:
            return parseHexPattern(searchText)
        case .asciiString:
            return Array(searchText.utf8)
        }
    }

    func replacementBytes() -> [UInt8]? {
        switch searchMode {
        case .hexPattern:
            return parseHexPattern(replaceText)
        case .asciiString:
            return Array(replaceText.utf8)
        }
    }

    func parseHexPattern(_ text: String) -> [UInt8]? {
        Self.parseHexPattern(text)
    }

    static func parseHexPattern(_ text: String) -> [UInt8]? {
        let stripped = text.replacingOccurrences(of: " ", with: "")
        guard !stripped.isEmpty else { return nil }
        guard stripped.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        var index = stripped.startIndex
        while index < stripped.endIndex {
            let nextIndex = stripped.index(index, offsetBy: 2)
            let hexPair = stripped[index..<nextIndex]
            guard let byte = UInt8(hexPair, radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }
}

/// Observable search state for hex find/replace, analogous to `SearchState` for text.
final class HexSearchState: ObservableObject {

    // MARK: - Published state

    @Published var searchText: String = ""
    @Published var replaceText: String = ""
    @Published var searchMode: HexSearchMode = .hexPattern
    @Published var matches: [Range<Int>] = []
    @Published var currentMatchIndex: Int = 0
    @Published var isVisible: Bool = false
    @Published var showReplace: Bool = false

    // MARK: - Go-to-offset state

    @Published var isGoToOffsetVisible: Bool = false

    // MARK: - Search

    /// Scan `data` for all non-overlapping occurrences of the current query.
    func findMatches(in data: Data) {
        var session = currentSession()
        session.findMatches(in: data)
        apply(session)
    }

    // MARK: - Navigation

    func findNext() {
        var session = currentSession()
        session.findNext()
        apply(session)
    }

    func findPrevious() {
        var session = currentSession()
        session.findPrevious()
        apply(session)
    }

    // MARK: - Replace

    /// Replace the current match in the hex document.
    func replace(in hexDocument: HexDocument) {
        var session = currentSession()
        guard !session.matches.isEmpty, session.currentMatchIndex < session.matches.count else { return }
        guard let replacement = session.replacementBytes() else { return }

        let match = session.matches[session.currentMatchIndex]
        applyReplacement(in: hexDocument, range: match, replacement: replacement)
        session.findMatches(in: hexDocument.currentData)
        apply(session)
    }

    /// Replace all matches in the hex document.
    func replaceAll(in hexDocument: HexDocument) {
        var session = currentSession()
        guard !session.matches.isEmpty else { return }
        guard let replacement = session.replacementBytes() else { return }

        // Replace in reverse order to keep earlier offsets valid.
        for match in session.matches.reversed() {
            applyReplacement(in: hexDocument, range: match, replacement: replacement)
        }
        session.findMatches(in: hexDocument.currentData)
        apply(session)
    }

    // MARK: - Helpers

    /// Parse the search text into a byte array according to the current mode.
    func patternBytes() -> [UInt8]? {
        currentSession().patternBytes()
    }

    /// Parse the replace text into a byte array according to the current mode.
    private func replacementBytes() -> [UInt8]? {
        currentSession().replacementBytes()
    }

    /// Parse a hex string like "FF D8 FF E0" or "ffd8ffe0" into bytes.
    ///
    /// Accepts space-separated or contiguous hex digit pairs. Returns nil on
    /// invalid input (odd number of non-space characters, non-hex characters).
    func parseHexPattern(_ text: String) -> [UInt8]? {
        HexSearchSession.parseHexPattern(text)
    }

    /// Apply a single replacement: delete old bytes then insert new ones.
    private func applyReplacement(in hexDocument: HexDocument, range: Range<Int>, replacement: [UInt8]) {
        // Delete old bytes (in reverse to keep indices stable).
        for i in stride(from: range.upperBound - 1, through: range.lowerBound, by: -1) {
            hexDocument.deleteByte(at: i)
        }
        // Insert replacement bytes.
        for (i, byte) in replacement.enumerated() {
            hexDocument.insertByte(byte, at: range.lowerBound + i)
        }
    }

    private func currentSession() -> HexSearchSession {
        HexSearchSession(
            searchText: searchText,
            replaceText: replaceText,
            searchMode: searchMode,
            matches: matches,
            currentMatchIndex: currentMatchIndex
        )
    }

    private func apply(_ session: HexSearchSession) {
        matches = session.matches
        currentMatchIndex = session.currentMatchIndex
    }
}
