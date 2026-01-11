//
//  DocumentExporter.swift
//  qw
//
//  Export functionality for documents: Print, PDF, PNG
//

import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// Handles document export to various formats
class DocumentExporter {
    
    // MARK: - Properties
    
    private let text: String
    private let fileType: SupportedFileType
    private let theme: SyntaxTheme
    private let includeLineNumbers: Bool
    private let fontSize: CGFloat
    private let fontName: String
    
    // MARK: - Initialization
    
    init(
        text: String,
        fileType: SupportedFileType,
        theme: SyntaxTheme,
        includeLineNumbers: Bool,
        fontSize: CGFloat = 12,
        fontName: String = "Menlo"
    ) {
        self.text = text
        self.fileType = fileType
        self.theme = theme
        self.includeLineNumbers = includeLineNumbers
        self.fontSize = fontSize
        self.fontName = fontName
    }
    
    // MARK: - Convenience initializer from settings
    
    convenience init(text: String, fileType: SupportedFileType, colorScheme: ColorScheme) {
        let settings = EditorSettingsManager.shared
        let theme = settings.syntaxTheme(for: colorScheme)
        
        self.init(
            text: text,
            fileType: fileType,
            theme: theme,
            includeLineNumbers: settings.showLineNumbers,
            fontSize: settings.fontSize,
            fontName: settings.selectedFont.fontName
        )
    }
    
    // MARK: - Font Helper
    
    private func getFont(size: CGFloat? = nil) -> NSFont {
        let size = size ?? fontSize
        if fontName == "Menlo" || fontName.isEmpty {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return NSFont(name: fontName, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    
    // MARK: - Create Attributed String
    
    private func createAttributedString() -> NSAttributedString {
        let lines = text.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        let highlighter = SyntaxHighlighter(fileType: fileType, theme: theme)
        let font = getFont()
        
        // Calculate line number width
        let lineNumberWidth: CGFloat = includeLineNumbers ? 50 : 0
        let lineCount = lines.count
        let maxLineDigits = String(lineCount).count
        
        // Paragraph style for line spacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        
        for (index, line) in lines.enumerated() {
            // Add line number if enabled
            if includeLineNumbers {
                let lineNumber = String(format: "%\(maxLineDigits)d  ", index + 1)
                let lineNumberAttrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(theme.lineNumber),
                    .paragraphStyle: paragraphStyle
                ]
                result.append(NSAttributedString(string: lineNumber, attributes: lineNumberAttrs))
            }
            
            // Apply syntax highlighting to the line
            let tokens = highlighter.tokenize(line)
            
            if tokens.isEmpty {
                // No tokens, use plain text
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(theme.plain),
                    .paragraphStyle: paragraphStyle
                ]
                result.append(NSAttributedString(string: line, attributes: attrs))
            } else {
                // Apply tokens
                var lastEnd = line.startIndex
                
                for token in tokens {
                    // Add any gap before token
                    if token.range.lowerBound > lastEnd {
                        let gap = String(line[lastEnd..<token.range.lowerBound])
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: NSColor(theme.plain),
                            .paragraphStyle: paragraphStyle
                        ]
                        result.append(NSAttributedString(string: gap, attributes: attrs))
                    }
                    
                    // Add token
                    let tokenText = String(line[token.range])
                    let color = theme.color(for: token.type)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: NSColor(color),
                        .paragraphStyle: paragraphStyle
                    ]
                    result.append(NSAttributedString(string: tokenText, attributes: attrs))
                    
                    lastEnd = token.range.upperBound
                }
                
                // Add any remaining text after last token
                if lastEnd < line.endIndex {
                    let remainder = String(line[lastEnd...])
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: NSColor(theme.plain),
                        .paragraphStyle: paragraphStyle
                    ]
                    result.append(NSAttributedString(string: remainder, attributes: attrs))
                }
            }
            
            // Add newline (except for last line)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        
        return result
    }
    
    // MARK: - Print
    
    func print() {
        let attributedString = createAttributedString()
        
        // Create text view for printing
        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792)) // Letter size
        printView.textStorage?.setAttributedString(attributedString)
        printView.backgroundColor = NSColor(theme.background)
        
        // Create print info
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        
        // Create print operation
        let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        
        printOperation.run()
    }
    
    // MARK: - Export to PDF
    
    func exportToPDF(to url: URL) throws {
        let attributedString = createAttributedString()
        
        // Page size (Letter)
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 36
        let contentWidth = pageWidth - (margin * 2)
        let contentHeight = pageHeight - (margin * 2)
        
        // Calculate total content size
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(size: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        
        // Force layout
        layoutManager.ensureLayout(for: textContainer)
        
        // Get total text height
        let usedRect = layoutManager.usedRect(for: textContainer)
        
        // Calculate number of pages
        let totalPages = max(1, Int(ceil(usedRect.height / contentHeight)))
        
        // Create PDF context
        var pdfData = Data()
        let consumer = CGDataConsumer(data: pdfData as! CFMutableData)!
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.pdfCreationFailed
        }
        
        // Draw each page
        for pageIndex in 0..<totalPages {
            pdfContext.beginPDFPage(nil)
            
            // Fill background
            pdfContext.setFillColor(NSColor(theme.background).cgColor)
            pdfContext.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            
            // Create graphics context for this page
            let nsGraphicsContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsGraphicsContext
            
            // Calculate text range for this page
            let yOffset = CGFloat(pageIndex) * contentHeight
            let visibleRect = NSRect(x: 0, y: yOffset, width: contentWidth, height: contentHeight)
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            
            // Transform for this page
            let transform = NSAffineTransform()
            transform.translateX(by: margin, yBy: pageHeight - margin)
            transform.scaleX(by: 1.0, yBy: -1.0)
            transform.translateX(by: 0, yBy: -yOffset)
            transform.concat()
            
            // Draw the text
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
            
            NSGraphicsContext.restoreGraphicsState()
            pdfContext.endPDFPage()
        }
        
        pdfContext.closePDF()
        
        // Write using proper PDF data extraction
        try generatePDFData(attributedString: attributedString, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin).write(to: url)
    }
    
    private func generatePDFData(attributedString: NSAttributedString, pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat) -> Data {
        let contentWidth = pageWidth - (margin * 2)
        let contentHeight = pageHeight - (margin * 2)
        
        let pdfData = NSMutableData()
        
        // Create text view for rendering
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        textView.textStorage?.setAttributedString(attributedString)
        textView.backgroundColor = NSColor(theme.background)
        
        // Calculate total height
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
        
        // Resize text view to fit all content
        textView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: usedRect.height)
        
        // Number of pages
        let totalPages = max(1, Int(ceil(usedRect.height / contentHeight)))
        
        // Create PDF
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        
        for pageIndex in 0..<totalPages {
            let pageInfo: [CFString: Any] = [
                kCGPDFContextMediaBox: NSValue(rect: mediaBox)
            ]
            pdfContext.beginPDFPage(pageInfo as CFDictionary)
            
            // Fill background
            pdfContext.setFillColor(NSColor(theme.background).cgColor)
            pdfContext.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            
            let nsContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext
            
            // Calculate which portion of text to draw
            let yOffset = CGFloat(pageIndex) * contentHeight
            
            // Set up transform: move origin to content area and flip for text
            let transform = NSAffineTransform()
            transform.translateX(by: margin, yBy: margin + contentHeight)
            transform.scaleX(by: 1.0, yBy: -1.0)
            transform.concat()
            
            // Draw text for this page
            textView.frame = NSRect(x: 0, y: -yOffset, width: contentWidth, height: usedRect.height)
            textView.draw(NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
            
            NSGraphicsContext.restoreGraphicsState()
            pdfContext.endPDFPage()
        }
        
        pdfContext.closePDF()
        
        return pdfData as Data
    }
    
    // MARK: - Export to PNG
    
    func exportToPNG(to url: URL) throws {
        let attributedString = createAttributedString()
        
        // Create text view for rendering
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 10
        layoutManager.addTextContainer(textContainer)
        
        // Force layout calculation
        layoutManager.ensureLayout(for: textContainer)
        
        // Get content size
        let usedRect = layoutManager.usedRect(for: textContainer)
        let padding: CGFloat = 20
        let width = usedRect.width + (padding * 2)
        let height = usedRect.height + (padding * 2)
        
        // Create bitmap
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * 2), // 2x for retina
            pixelsHigh: Int(height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        
        bitmapRep.size = NSSize(width: width, height: height)
        
        // Create graphics context
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            throw ExportError.pngCreationFailed
        }
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        // Fill background
        NSColor(theme.background).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        
        // Draw text
        let drawPoint = NSPoint(x: padding, y: padding)
        layoutManager.drawBackground(forGlyphRange: NSRange(location: 0, length: textStorage.length), at: drawPoint)
        layoutManager.drawGlyphs(forGlyphRange: NSRange(location: 0, length: textStorage.length), at: drawPoint)
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Save PNG
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw ExportError.pngCreationFailed
        }
        
        try pngData.write(to: url)
    }
    
    // MARK: - Show Export Dialogs
    
    func showPDFExportDialog(defaultName: String = "document") {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Export as PDF"
        savePanel.message = "Choose a location to save the PDF"
        savePanel.nameFieldLabel = "File Name:"
        savePanel.nameFieldStringValue = "\(defaultName).pdf"
        
        savePanel.begin { [weak self] response in
            if response == .OK, let url = savePanel.url {
                do {
                    try self?.exportToPDF(to: url)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } catch {
                    self?.showError("Failed to export PDF: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func showPNGExportDialog(defaultName: String = "document") {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Export as PNG"
        savePanel.message = "Choose a location to save the image"
        savePanel.nameFieldLabel = "File Name:"
        savePanel.nameFieldStringValue = "\(defaultName).png"
        
        savePanel.begin { [weak self] response in
            if response == .OK, let url = savePanel.url {
                do {
                    try self?.exportToPNG(to: url)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } catch {
                    self?.showError("Failed to export PNG: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Export Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Export Errors

enum ExportError: Error, LocalizedError {
    case pdfCreationFailed
    case pngCreationFailed
    case invalidInput
    
    var errorDescription: String? {
        switch self {
        case .pdfCreationFailed:
            return "Failed to create PDF document"
        case .pngCreationFailed:
            return "Failed to create PNG image"
        case .invalidInput:
            return "Invalid input file"
        }
    }
}

// MARK: - CLI Export Support

/// Command-line export functionality
class CLIExporter {
    
    enum OutputFormat: String {
        case pdf
        case png
    }
    
    /// Export a file to PDF or PNG from command line
    static func exportFile(
        inputPath: String,
        outputPath: String,
        format: OutputFormat,
        includeLineNumbers: Bool = true,
        theme: SyntaxTheme = .dark,
        fontSize: CGFloat = 12
    ) throws {
        // Read input file
        let inputURL = URL(fileURLWithPath: inputPath)
        let text = try String(contentsOf: inputURL, encoding: .utf8)
        let fileType = SupportedFileType.from(url: inputURL)
        
        // Create exporter
        let exporter = DocumentExporter(
            text: text,
            fileType: fileType,
            theme: theme,
            includeLineNumbers: includeLineNumbers,
            fontSize: fontSize,
            fontName: "Menlo"
        )
        
        // Export
        let outputURL = URL(fileURLWithPath: outputPath)
        
        switch format {
        case .pdf:
            try exporter.exportToPDF(to: outputURL)
        case .png:
            try exporter.exportToPNG(to: outputURL)
        }
    }
    
    /// Print a file (opens print dialog)
    static func printFile(
        inputPath: String,
        includeLineNumbers: Bool = true,
        theme: SyntaxTheme = .dark,
        fontSize: CGFloat = 12
    ) throws {
        // Read input file
        let inputURL = URL(fileURLWithPath: inputPath)
        let text = try String(contentsOf: inputURL, encoding: .utf8)
        let fileType = SupportedFileType.from(url: inputURL)
        
        // Create exporter and print
        let exporter = DocumentExporter(
            text: text,
            fileType: fileType,
            theme: theme,
            includeLineNumbers: includeLineNumbers,
            fontSize: fontSize,
            fontName: "Menlo"
        )
        
        exporter.print()
    }
}

#endif
