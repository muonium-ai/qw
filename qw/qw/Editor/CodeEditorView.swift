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
    @ObservedObject private var settings = EditorSettingsManager.shared
    
    @State private var lineCount: Int = 1
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var actualLineHeight: CGFloat = 0
    
    private var theme: SyntaxTheme {
        settings.syntaxTheme(for: colorScheme)
    }

    private var themeKey: String {
        let scheme = colorScheme == .dark ? "dark" : "light"
        return "\(settings.themeName)-\(scheme)"
    }

    private var editorLineHeight: CGFloat {
        #if os(macOS)
        // Use same font logic as MacOSTextEditor.getFont()
        let fontName = settings.selectedFont.fontName
        let font: NSFont
        if fontName == "Menlo" || fontName.isEmpty {
            font = NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
        } else {
            font = NSFont(name: fontName, size: settings.fontSize)
                ?? NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
        }
        let baseLineHeight = NSLayoutManager().defaultLineHeight(for: font)
        return baseLineHeight * CGFloat(settings.lineHeight)
        #else
        let font = settings.uiFont()
        return font.lineHeight * CGFloat(settings.lineHeight)
        #endif
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Line numbers - synchronized with text view scroll
            if settings.showLineNumbers {
                LineNumbersView(
                    lineCount: lineCount,
                    theme: theme,
                    scrollOffset: scrollOffset,
                    contentHeight: contentHeight,
                    fontSize: settings.fontSize,
                    fontName: settings.selectedFont.fontName,
                    lineHeight: actualLineHeight > 0 ? actualLineHeight : editorLineHeight
                )
                .frame(width: 50)
                .accessibilityIdentifier("lineNumbers")
                
                Divider()
            }
            
            // Editor - no wrapping ScrollView since NSTextView has its own
            #if os(macOS)
            MacOSTextEditor(
                text: $text,
                fileType: fileType,
                themeName: themeKey,
                theme: theme,
                fontSize: settings.fontSize,
                lineHeightMultiple: settings.lineHeight,
                fontName: settings.selectedFont.fontName,
                onLineCountChange: { count in
                    lineCount = count
                },
                onScrollChange: { offset, height, lineHeight in
                    scrollOffset = offset
                    contentHeight = height
                    if lineHeight > 0 {
                        actualLineHeight = lineHeight
                    }
                }
            )
            .accessibilityIdentifier("codeEditor")
            .id("\(settings.fontSize)-\(settings.fontName)-\(themeKey)")
            #else
            iOSTextEditor(
                text: $text,
                fileType: fileType,
                themeName: themeKey,
                theme: theme,
                fontSize: settings.fontSize,
                lineHeightMultiple: settings.lineHeight,
                fontName: settings.selectedFont.fontName,
                onLineCountChange: { count in
                    lineCount = count
                },
                onScrollChange: { offset, height, lineHeight in
                    scrollOffset = offset
                    contentHeight = height
                    if lineHeight > 0 {
                        actualLineHeight = lineHeight
                    }
                }
            )
            .accessibilityIdentifier("codeEditor")
            .id("\(settings.fontSize)-\(settings.fontName)-\(themeKey)")
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

/// Line numbers view - synchronized with text view scroll using Canvas for efficient rendering
struct LineNumbersView: View {
    let lineCount: Int
    let theme: SyntaxTheme
    let scrollOffset: CGFloat
    let contentHeight: CGFloat
    let fontSize: Double
    let fontName: String
    let lineHeight: CGFloat
    
    // Match the text view's top inset
    private var topInset: CGFloat {
        max(4, CGFloat(fontSize * 1.5))
    }

    private var lineNumberFont: Font {
        if fontName.isEmpty {
            return .system(size: fontSize, design: .monospaced)
        }
        return .custom(fontName, size: fontSize)
    }
    
    var body: some View {
        Canvas { context, size in
            // Fill background
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(theme.background.opacity(0.5))
            )
            
            let visibleHeight = size.height
            let totalLines = max(1, lineCount)
            
            // Account for the text container inset when calculating visible lines
            let adjustedScrollOffset = max(0, scrollOffset - topInset)
            
            // Calculate which lines are visible
            let firstVisibleLine = max(1, Int(adjustedScrollOffset / lineHeight) + 1)
            let visibleLineCount = Int(visibleHeight / lineHeight) + 3 // Extra buffer
            let lastVisibleLine = min(totalLines, firstVisibleLine + visibleLineCount)
            
            // Guard against invalid ranges
            guard firstVisibleLine <= lastVisibleLine else { return }
            
            // Draw each visible line number
            for lineNumber in firstVisibleLine...lastVisibleLine {
                // Position includes the top inset offset
                let yPosition = topInset + CGFloat(lineNumber - 1) * lineHeight - scrollOffset
                
                // Skip if outside visible area
                if yPosition < -lineHeight || yPosition > visibleHeight {
                    continue
                }
                
                let text = Text("\(lineNumber)")
                    .font(lineNumberFont)
                    .foregroundColor(theme.lineNumber)
                
                // Right-align the line number
                let resolved = context.resolve(text)
                let textSize = resolved.measure(in: CGSize(width: size.width, height: lineHeight))
                let xPosition = size.width - textSize.width - 8
                
                context.draw(resolved, at: CGPoint(x: xPosition, y: yPosition + (lineHeight - textSize.height) / 2), anchor: .topLeading)
            }
        }
        .clipped()
    }
}

#if os(macOS)
import AppKit

/// macOS native text editor using NSTextView
struct MacOSTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fileType: SupportedFileType
    let themeName: String
    let theme: SyntaxTheme
    let fontSize: Double
    let lineHeightMultiple: Double
    let fontName: String
    let onLineCountChange: (Int) -> Void
    let onScrollChange: (CGFloat, CGFloat, CGFloat) -> Void  // offset, height, lineHeight
    
    private func textContainerInset() -> NSSize {
        let insetHeight = max(4, CGFloat(fontSize * 1.5))
        return NSSize(width: 4, height: insetHeight)
    }
    
    private func getFont() -> NSFont {
        if fontName == "Menlo" || fontName.isEmpty {
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        return NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private func paragraphStyle(for font: NSFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let baseLineHeight = NSLayoutManager().defaultLineHeight(for: font)
        let lineHeight = baseLineHeight * CGFloat(lineHeightMultiple)
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }

    private func applyParagraphStyle(_ style: NSParagraphStyle, to textView: NSTextView) {
        textView.defaultParagraphStyle = style
        var typingAttributes = textView.typingAttributes
        typingAttributes[.paragraphStyle] = style
        textView.typingAttributes = typingAttributes
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        let font = getFont()
        
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = font
        textView.backgroundColor = NSColor(theme.background)
        textView.textColor = NSColor(theme.plain)
        textView.insertionPointColor = NSColor(theme.plain)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        // Prevent blank regions during fast scrolling.
        textView.layoutManager?.allowsNonContiguousLayout = false

        let paragraphStyle = paragraphStyle(for: font)
        applyParagraphStyle(paragraphStyle, to: textView)
        
        // Configure text container for proper line height
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        
        textView.textContainerInset = textContainerInset()
        
        // Add extra height to the text container to allow scrolling past last lines
        // This is done by increasing the container's height tracking
        if let textContainer = textView.textContainer {
            textContainer.heightTracksTextView = false
        }
        
        // Store font info in coordinator
        context.coordinator.currentFont = font
        
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
        scrollView.drawsBackground = true
        scrollView.contentView.backgroundColor = NSColor(theme.background)
        
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
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
        context.coordinator.parent = self
        
        let font = getFont()
        var needsHighlight = false
        
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            needsHighlight = true
        }
        
        // Update font if changed
        if context.coordinator.currentFont != font {
            context.coordinator.currentFont = font
            textView.font = font
            needsHighlight = true
        }

        if context.coordinator.lineHeightMultiple != lineHeightMultiple {
            context.coordinator.lineHeightMultiple = lineHeightMultiple
            needsHighlight = true
        }
        
        // Update colors
        textView.backgroundColor = NSColor(theme.background)
        textView.insertionPointColor = NSColor(theme.plain)
        scrollView.backgroundColor = NSColor(theme.background)
        scrollView.contentView.backgroundColor = NSColor(theme.background)
        
        if context.coordinator.fileType != fileType {
            context.coordinator.fileType = fileType
            needsHighlight = true
        }
        
        if context.coordinator.themeName != themeName {
            context.coordinator.themeName = themeName
            context.coordinator.theme = theme
            needsHighlight = true
        } else {
            context.coordinator.theme = theme
        }
        
        let currentInset = textView.textContainerInset
        let desiredInset = textContainerInset()
        if currentInset.width != desiredInset.width || currentInset.height != desiredInset.height {
            textView.textContainerInset = desiredInset
        }

        let paragraphStyle = paragraphStyle(for: font)
        applyParagraphStyle(paragraphStyle, to: textView)
        
        if needsHighlight {
            context.coordinator.applySyntaxHighlighting(to: textView)
        }
        
        // Report current scroll position and line count
        let scrollOffset = scrollView.contentView.bounds.origin.y
        let contentHeight = textView.frame.height
        let lineHeight = context.coordinator.getActualLineHeight(from: textView)
        onScrollChange(scrollOffset, contentHeight, lineHeight)
        
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
        var themeName: String
        var currentFont: NSFont
        var lineHeightMultiple: Double
        private var isUpdating = false
        
        init(_ parent: MacOSTextEditor) {
            self.parent = parent
            self.fileType = parent.fileType
            self.theme = parent.theme
            self.themeName = parent.themeName
            self.currentFont = parent.getFont()
            self.lineHeightMultiple = parent.lineHeightMultiple
        }
        
        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                  let scrollView = clipView.superview as? NSScrollView,
                  let textView = scrollView.documentView as? NSTextView else { return }
            
            let scrollOffset = clipView.bounds.origin.y
            let contentHeight = textView.frame.height
            let lineHeight = getActualLineHeight(from: textView)
            parent.onScrollChange(scrollOffset, contentHeight, lineHeight)
        }
        
        func getActualLineHeight(from textView: NSTextView) -> CGFloat {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  textView.string.count > 0 else {
                return 0
            }
            
            // Get the line height from the first line's used rect
            let glyphRange = layoutManager.glyphRange(for: textContainer)
            if glyphRange.length > 0 {
                var lineRange = NSRange()
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &lineRange)
                return lineRect.height
            }
            return 0
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
            
            // Skip syntax highlighting for very large files (> 100KB) to prevent hang/crash
            let maxHighlightSize = 100_000
            if text.utf16.count > maxHighlightSize {
                // Just apply plain styling for large files
                let fullRange = NSRange(location: 0, length: text.utf16.count)
                let paragraphStyle = parent.paragraphStyle(for: currentFont)
                textView.textStorage?.beginEditing()
                textView.textStorage?.setAttributes([
                    .font: currentFont,
                    .foregroundColor: NSColor(theme.plain),
                    .paragraphStyle: paragraphStyle
                ], range: fullRange)
                textView.textStorage?.endEditing()
                return
            }
            
            let highlighter = SyntaxHighlighter(fileType: fileType, theme: theme)
            
            // Store selection
            let selectedRanges = textView.selectedRanges
            
            // Batch all edits to prevent repeated layout passes
            textView.textStorage?.beginEditing()
            
            // Reset to plain style with current font
            let fullRange = NSRange(location: 0, length: text.utf16.count)
            let paragraphStyle = parent.paragraphStyle(for: currentFont)
            textView.textStorage?.setAttributes([
                .font: currentFont,
                .foregroundColor: NSColor(theme.plain),
                .paragraphStyle: paragraphStyle
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
            
            textView.textStorage?.endEditing()
            
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
    let themeName: String
    let theme: SyntaxTheme
    let fontSize: Double
    let lineHeightMultiple: Double
    let fontName: String
    let onLineCountChange: (Int) -> Void
    let onScrollChange: (CGFloat, CGFloat, CGFloat) -> Void  // offset, height, lineHeight
    
    private func getFont() -> UIFont {
        if fontName == "Menlo" || fontName.isEmpty {
            return UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        return UIFont(name: fontName, size: fontSize)
            ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private func paragraphStyle(for font: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let lineHeight = font.lineHeight * CGFloat(lineHeightMultiple)
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }

    private func applyParagraphStyle(_ style: NSParagraphStyle, to textView: UITextView, font: UIFont) {
        var typingAttributes = textView.typingAttributes
        typingAttributes[.paragraphStyle] = style
        typingAttributes[.font] = font
        textView.typingAttributes = typingAttributes
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        let font = getFont()
        
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = font
        textView.backgroundColor = UIColor(theme.background)
        textView.textColor = UIColor(theme.plain)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.keyboardType = .asciiCapable
        textView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        textView.text = text

        let paragraphStyle = paragraphStyle(for: font)
        applyParagraphStyle(paragraphStyle, to: textView, font: font)
        
        context.coordinator.currentFont = font
        
        // Report initial line count
        let lineCount = text.components(separatedBy: "\n").count
        onLineCountChange(lineCount)
        
        // Apply syntax highlighting
        context.coordinator.applySyntaxHighlighting(to: textView)
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        let font = getFont()
        var needsHighlight = false
        
        if textView.text != text {
            let selectedRange = textView.selectedRange
            textView.text = text
            textView.selectedRange = selectedRange
            needsHighlight = true
        }
        
        // Update font if changed
        if context.coordinator.currentFont != font {
            context.coordinator.currentFont = font
            textView.font = font
            needsHighlight = true
        }

        if context.coordinator.lineHeightMultiple != lineHeightMultiple {
            context.coordinator.lineHeightMultiple = lineHeightMultiple
            needsHighlight = true
        }
        
        textView.backgroundColor = UIColor(theme.background)
        
        if context.coordinator.fileType != fileType {
            context.coordinator.fileType = fileType
            needsHighlight = true
        }
        
        if context.coordinator.themeName != themeName {
            context.coordinator.themeName = themeName
            context.coordinator.theme = theme
            needsHighlight = true
        } else {
            context.coordinator.theme = theme
        }
        
        if needsHighlight {
            context.coordinator.applySyntaxHighlighting(to: textView)
        }

        let paragraphStyle = paragraphStyle(for: font)
        applyParagraphStyle(paragraphStyle, to: textView, font: font)
        
        // Report scroll position and line count
        let lineHeight = context.coordinator.getActualLineHeight(from: textView)
        onScrollChange(textView.contentOffset.y, textView.contentSize.height, lineHeight)
        
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
        var themeName: String
        var currentFont: UIFont
        var lineHeightMultiple: Double
        private var isUpdating = false
        
        init(_ parent: iOSTextEditor) {
            self.parent = parent
            self.fileType = parent.fileType
            self.theme = parent.theme
            self.themeName = parent.themeName
            self.currentFont = parent.getFont()
            self.lineHeightMultiple = parent.lineHeightMultiple
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? UITextView else { return }
            let lineHeight = getActualLineHeight(from: textView)
            parent.onScrollChange(textView.contentOffset.y, textView.contentSize.height, lineHeight)
        }
        
        func getActualLineHeight(from textView: UITextView) -> CGFloat {
            guard let font = textView.font else { return 0 }
            return font.lineHeight * CGFloat(lineHeightMultiple)
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
            
            // Skip syntax highlighting for very large files (> 100KB) to prevent hang/crash
            let maxHighlightSize = 100_000
            if text.utf16.count > maxHighlightSize {
                let paragraphStyle = parent.paragraphStyle(for: currentFont)
                let attributedText = NSMutableAttributedString(string: text, attributes: [
                    .font: currentFont,
                    .foregroundColor: UIColor(theme.plain),
                    .paragraphStyle: paragraphStyle
                ])
                let selectedRange = textView.selectedRange
                textView.attributedText = attributedText
                textView.selectedRange = selectedRange
                return
            }
            
            let highlighter = SyntaxHighlighter(fileType: fileType, theme: theme)
            
            let selectedRange = textView.selectedRange
            
            let paragraphStyle = parent.paragraphStyle(for: currentFont)
            let attributedText = NSMutableAttributedString(string: text, attributes: [
                .font: currentFont,
                .foregroundColor: UIColor(theme.plain),
                .paragraphStyle: paragraphStyle
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
