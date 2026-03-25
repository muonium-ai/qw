//
//  HexSearchView.swift
//  qw
//
//  Search/replace bar for hex mode, styled similarly to SearchReplaceView.
//  Ticket: T-000022
//

import SwiftUI

/// Search and replace bar for hex editing mode.
struct HexSearchView: View {
    @ObservedObject var state: HexSearchState
    let data: Data
    let hexDocument: HexDocument?

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        EditorSettingsManager.shared.syntaxTheme(for: colorScheme).background
    }

    var body: some View {
        VStack(spacing: 8) {
            // Search row
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                Picker("", selection: $state.searchMode) {
                    ForEach(HexSearchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .onChange(of: state.searchMode) { _, _ in
                    state.findMatches(in: data)
                }

                TextField(state.searchMode == .hexPattern ? "FF D8 FF E0" : "Search ASCII", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("hexSearchField")
                    #if os(macOS)
                    .onSubmit {
                        state.findMatches(in: data)
                        if !state.matches.isEmpty {
                            state.findNext()
                        }
                    }
                    #endif
                    .onChange(of: state.searchText) { _, _ in
                        state.findMatches(in: data)
                    }

                if !state.searchText.isEmpty {
                    Text("\(state.matches.isEmpty ? 0 : state.currentMatchIndex + 1)/\(state.matches.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 40)

                    Button(action: { state.findPrevious() }) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)

                    Button(action: { state.findNext() }) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                }

                if hexDocument != nil {
                    Button(action: { state.showReplace.toggle() }) {
                        Image(systemName: state.showReplace ? "chevron.up.square" : "arrow.left.arrow.right")
                    }
                    .buttonStyle(.borderless)
                }

                Button(action: { state.isVisible = false }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .cornerRadius(8)

            // Replace row (editable mode only)
            if state.showReplace, let doc = hexDocument {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundColor(.secondary)

                    TextField(state.searchMode == .hexPattern ? "Replace hex" : "Replace ASCII", text: $state.replaceText)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("hexReplaceField")

                    Button("Replace") {
                        state.replace(in: doc)
                    }
                    .buttonStyle(.borderless)
                    .disabled(state.searchText.isEmpty || state.matches.isEmpty)

                    Button("All") {
                        state.replaceAll(in: doc)
                    }
                    .buttonStyle(.borderless)
                    .disabled(state.searchText.isEmpty || state.matches.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .cornerRadius(8)
            }
        }
        .padding(8)
    }
}
