//
//  CodeEditorView.swift
//  qw
//
//  The main code editor view with syntax highlighting
//

import SwiftUI

/// A code editor view with syntax highlighting and line numbers
struct CodeEditorView: View {
    @Binding var text: String
    let fileType: SupportedFileType
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var lineCount: Int = 1
    @State private var scrollOffset: CGFloat = 0
    
    private var theme: SyntaxTheme {
        colorScheme == .dark ? .dark : .light
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                // Line numbers
                LineNumbersView(
                    lineCount: lineCount,
                    theme: theme
                )
                .frame(width: 50)
                
                Divider()
                
                // Editor
                ScrollView(.vertical, showsIndicators: true) {
                    HighlightedTextEditor(
                        text: $text,
                        fileType: fileType,
                        theme: theme,
                        onLineCountChange: { count in
                            lineCount = count
                        }
                    )
                    .frame(minHeight: geometry.size.height)
                }
            }
            .background(theme.background)
        }
        .onAppear {
            updateLineCount()
        }
        .onChange(of: text) { _, _ in
            updateLineCount()
        }
    }
    
    private func updateLineCount() {
        lineCount = max(1, text.components(separatedBy: "\n").count)
    }
}

/// Line numbers view
struct LineNumbersView: View {
    let lineCount: Int
    let theme: SyntaxTheme
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(1...max(1, lineCount), id: \.self) { line in
                    Text("\(line)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(theme.lineNumber)
                        .frame(height: 21) // Match line height
                        .padding(.horizontal, 8)
                }
            }
            .padding(.top, 8)
        }
        .background(theme.background.opacity(0.5))
    }
}

/// Text editor with syntax highlighting
struct HighlightedTextEditor: View {
    @Binding var text: String
    let fileType: SupportedFileType
    let theme: SyntaxTheme
    let onLineCountChange: (Int) -> Void
    
    var body: some View {
        #if os(macOS)
        MacOSTextEditor(
            text: $text,
            fileType: fileType,
            theme: theme,
            onLineCountChange: onLineCountChange
        )
        #else
        iOSTextEditor(
            text: $text,
            fileType: fileType,
            theme: theme,
            onLineCountChange: onLineCountChange
        )
        #endif
    }
}

#if os(macOS)
import AppKit

/// macOS native text editor using NSTextView
struct MacOSTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fileType: SupportedFileType
    let theme: SyntaxTheme
    let onLineCountChange: (Int) -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = NSColor(theme.background)
        textView.textColor = NSColor(theme.plain)
        textView.insertionPointColor = NSColor(theme.plain)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        // Configure text container
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        
        // Set initial text
        textView.string = text
        
        // Apply syntax highlighting
        context.coordinator.applySyntaxHighlighting(to: textView)
        
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = NSColor(theme.background)
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        
        // Update colors
        textView.backgroundColor = NSColor(theme.background)
        textView.textColor = NSColor(theme.plain)
        textView.insertionPointColor = NSColor(theme.plain)
        
        context.coordinator.fileType = fileType
        context.coordinator.theme = theme
        context.coordinator.applySyntaxHighlighting(to: textView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacOSTextEditor
        var fileType: SupportedFileType
        var theme: SyntaxTheme
        private var isUpdating = false
        
        init(_ parent: MacOSTextEditor) {
            self.parent = parent
            self.fileType = parent.fileType
            self.theme = parent.theme
        }
        
        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            
            parent.text = textView.string
            
            let lineCount = textView.string.components(separatedBy: "\n").count
            parent.onLineCountChange(lineCount)
            
            // Apply syntax highlighting
            applySyntaxHighlighting(to: textView)
        }
        
        func applySyntaxHighlighting(to textView: NSTextView) {
            isUpdating = true
            defer { isUpdating = false }
            
            let text = textView.string
            let highlighter = SyntaxHighlighter(fileType: fileType, theme: theme)
            
            // Store selection
            let selectedRanges = textView.selectedRanges
            
            // Reset to plain style
            let fullRange = NSRange(location: 0, length: text.utf16.count)
            textView.textStorage?.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor(theme.plain)
            ], range: fullRange)
            
            // Apply highlighted tokens using tokens directly
            let tokens = highlighter.tokenize(text)
            for token in tokens {
                let nsRange = NSRange(token.range, in: text)
                if nsRange.location != NSNotFound && nsRange.location + nsRange.length <= text.utf16.count {
                    let color = theme.color(for: token.type)
                    textView.textStorage?.addAttribute(.foregroundColor, value: NSColor(color), range: nsRange)
                }
            }
            
            // Restore selection
            textView.selectedRanges = selectedRanges
        }
    }
}
#endif

#if os(iOS)
import UIKit

/// iOS text editor using UITextView
struct iOSTextEditor: UIViewRepresentable {
    @Binding var text: String
    let fileType: SupportedFileType
    let theme: SyntaxTheme
    let onLineCountChange: (Int) -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = UIColor(theme.background)
        textView.textColor = UIColor(theme.plain)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.keyboardType = .asciiCapable
        textView.text = text
        
        // Apply syntax highlighting
        context.coordinator.applySyntaxHighlighting(to: textView)
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            let selectedRange = textView.selectedRange
            textView.text = text
            textView.selectedRange = selectedRange
        }
        
        textView.backgroundColor = UIColor(theme.background)
        textView.textColor = UIColor(theme.plain)
        
        context.coordinator.fileType = fileType
        context.coordinator.theme = theme
        context.coordinator.applySyntaxHighlighting(to: textView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: iOSTextEditor
        var fileType: SupportedFileType
        var theme: SyntaxTheme
        private var isUpdating = false
        
        init(_ parent: iOSTextEditor) {
            self.parent = parent
            self.fileType = parent.fileType
            self.theme = parent.theme
        }
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            
            parent.text = textView.text
            
            let lineCount = textView.text.components(separatedBy: "\n").count
            parent.onLineCountChange(lineCount)
            
            applySyntaxHighlighting(to: textView)
        }
        
        func applySyntaxHighlighting(to textView: UITextView) {
            isUpdating = true
            defer { isUpdating = false }
            
            let text = textView.text ?? ""
            let highlighter = SyntaxHighlighter(fileType: fileType, theme: theme)
            
            let selectedRange = textView.selectedRange
            
            let attributedText = NSMutableAttributedString(string: text, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor(theme.plain)
            ])
            
            // Apply syntax highlighting using tokens directly
            let tokens = highlighter.tokenize(text)
            for token in tokens {
                let nsRange = NSRange(token.range, in: text)
                if nsRange.location != NSNotFound && nsRange.location + nsRange.length <= text.utf16.count {
                    let color = theme.color(for: token.type)
                    attributedText.addAttribute(.foregroundColor, value: UIColor(color), range: nsRange)
                }
            }
            
            textView.attributedText = attributedText
            textView.selectedRange = selectedRange
        }
    }
}
#endif

#Preview {
    CodeEditorView(
        text: .constant("""
        # Hello World
        
        This is a **markdown** file with some code:
        
        ```swift
        func hello() {
            print("Hello, World!")
        }
        ```
        
        - Item 1
        - Item 2
        - Item 3
        """),
        fileType: .markdown
    )
}
