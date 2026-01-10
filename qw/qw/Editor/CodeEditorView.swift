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
    @State private var contentHeight: CGFloat = 0
    
    private var theme: SyntaxTheme {
        colorScheme == .dark ? .dark : .light
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Line numbers - synchronized with text view scroll
            LineNumbersView(
                lineCount: lineCount,
                theme: theme,
                scrollOffset: scrollOffset,
                contentHeight: contentHeight
            )
            .frame(width: 50)
            .accessibilityIdentifier("lineNumbers")
            
            Divider()
            
            // Editor - no wrapping ScrollView since NSTextView has its own
            #if os(macOS)
            MacOSTextEditor(
                text: $text,
                fileType: fileType,
                theme: theme,
                onLineCountChange: { count in
                    lineCount = count
                },
                onScrollChange: { offset, height in
                    scrollOffset = offset
                    contentHeight = height
                }
            )
            .accessibilityIdentifier("codeEditor")
            #else
            iOSTextEditor(
                text: $text,
                fileType: fileType,
                theme: theme,
                onLineCountChange: { count in
                    lineCount = count
                },
                onScrollChange: { offset, height in
                    scrollOffset = offset
                    contentHeight = height
                }
            )
            .accessibilityIdentifier("codeEditor")
            #endif
        }
        .background(theme.background)
        .accessibilityIdentifier("editorContainer")
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

/// Line numbers view - synchronized with text view scroll
struct LineNumbersView: View {
    let lineCount: Int
    let theme: SyntaxTheme
    let scrollOffset: CGFloat
    let contentHeight: CGFloat
    
    private let lineHeight: CGFloat = 21
    private let topPadding: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(1...max(1, lineCount), id: \.self) { line in
                        Text("\(line)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(theme.lineNumber)
                            .frame(height: lineHeight)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.top, topPadding)
                .background(theme.background.opacity(0.5))
            }
            .scrollDisabled(true)
            .offset(y: -scrollOffset)
        }
        .clipped()
        .background(theme.background.opacity(0.5))
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
    let onScrollChange: (CGFloat, CGFloat) -> Void
    
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
        
        // Configure text container for proper line height
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        
        // Remove default padding to align with line numbers
        textView.textContainerInset = NSSize(width: 0, height: 0)
        
        // Set initial text
        textView.string = text
        
        // Report initial line count
        let lineCount = text.components(separatedBy: "\n").count
        onLineCountChange(lineCount)
        
        // Apply syntax highlighting
        context.coordinator.applySyntaxHighlighting(to: textView)
        
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = NSColor(theme.background)
        
        // Observe scroll changes
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
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
        
        // Report current scroll position and line count
        let scrollOffset = scrollView.contentView.bounds.origin.y
        let contentHeight = textView.frame.height
        onScrollChange(scrollOffset, contentHeight)
        
        // Always report line count when view updates (handles file load)
        let lineCount = textView.string.components(separatedBy: "\n").count
        onLineCountChange(lineCount)
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
        
        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                  let scrollView = clipView.superview as? NSScrollView,
                  let textView = scrollView.documentView as? NSTextView else { return }
            
            let scrollOffset = clipView.bounds.origin.y
            let contentHeight = textView.frame.height
            parent.onScrollChange(scrollOffset, contentHeight)
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
    let onScrollChange: (CGFloat, CGFloat) -> Void
    
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
        textView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        textView.text = text
        
        // Report initial line count
        let lineCount = text.components(separatedBy: "\n").count
        onLineCountChange(lineCount)
        
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
        
        // Report scroll position and line count
        onScrollChange(textView.contentOffset.y, textView.contentSize.height)
        
        // Always report line count when view updates (handles file load)
        let lineCount = (textView.text ?? "").components(separatedBy: "\n").count
        onLineCountChange(lineCount)
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
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? UITextView else { return }
            parent.onScrollChange(textView.contentOffset.y, textView.contentSize.height)
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
