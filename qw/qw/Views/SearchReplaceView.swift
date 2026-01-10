//
//  SearchReplaceView.swift
//  qw
//
//  Search and Replace functionality for the editor
//

import SwiftUI
import Combine

#if os(macOS)
import AppKit
#endif

/// Search and Replace bar view
struct SearchReplaceView: View {
    @Binding var searchText: String
    @Binding var replaceText: String
    @Binding var isVisible: Bool
    @Binding var showReplace: Bool
    
    let onFindNext: () -> Void
    let onFindPrevious: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    
    @State private var matchCount: Int = 0
    @State private var currentMatch: Int = 0
    
    private var backgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Search row
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Find", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("searchField")
                    #if os(macOS)
                    .onSubmit {
                        onFindNext()
                    }
                    #endif
                
                if !searchText.isEmpty {
                    Text("\(currentMatch)/\(matchCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 40)
                    
                    Button(action: onFindPrevious) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("findPrevious")
                    
                    Button(action: onFindNext) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("findNext")
                }
                
                Button(action: { showReplace.toggle() }) {
                    Image(systemName: showReplace ? "chevron.up.square" : "arrow.left.arrow.right")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("toggleReplace")
                
                Button(action: { isVisible = false }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("closeSearch")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .cornerRadius(8)
            
            // Replace row (conditional)
            if showReplace {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundColor(.secondary)
                    
                    TextField("Replace", text: $replaceText)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("replaceField")
                    
                    Button("Replace") {
                        onReplace()
                    }
                    .buttonStyle(.borderless)
                    .disabled(searchText.isEmpty)
                    .accessibilityIdentifier("replaceButton")
                    
                    Button("All") {
                        onReplaceAll()
                    }
                    .buttonStyle(.borderless)
                    .disabled(searchText.isEmpty)
                    .accessibilityIdentifier("replaceAllButton")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .cornerRadius(8)
            }
        }
        .padding(8)
    }
    
    func updateMatchInfo(current: Int, total: Int) {
        currentMatch = current
        matchCount = total
    }
}

/// Search state manager
class SearchState: ObservableObject {
    @Published var searchText: String = ""
    @Published var replaceText: String = ""
    @Published var isVisible: Bool = false
    @Published var showReplace: Bool = false
    @Published var matches: [Range<String.Index>] = []
    @Published var currentMatchIndex: Int = 0
    
    func findMatches(in text: String) {
        guard !searchText.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }
        
        matches = []
        var searchStart = text.startIndex
        
        while let range = text.range(of: searchText, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            matches.append(range)
            searchStart = range.upperBound
        }
        
        if matches.isEmpty {
            currentMatchIndex = 0
        } else if currentMatchIndex >= matches.count {
            currentMatchIndex = matches.count - 1
        }
    }
    
    func findNext() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }
    
    func findPrevious() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = currentMatchIndex > 0 ? currentMatchIndex - 1 : matches.count - 1
    }
    
    func replace(in text: inout String) {
        guard !matches.isEmpty, currentMatchIndex < matches.count else { return }
        let range = matches[currentMatchIndex]
        text.replaceSubrange(range, with: replaceText)
        findMatches(in: text)
    }
    
    func replaceAll(in text: inout String) {
        guard !searchText.isEmpty else { return }
        text = text.replacingOccurrences(of: searchText, with: replaceText, options: .caseInsensitive)
        findMatches(in: text)
    }
}

#Preview {
    SearchReplaceView(
        searchText: .constant("test"),
        replaceText: .constant(""),
        isVisible: .constant(true),
        showReplace: .constant(true),
        onFindNext: {},
        onFindPrevious: {},
        onReplace: {},
        onReplaceAll: {}
    )
    .frame(width: 400)
}
