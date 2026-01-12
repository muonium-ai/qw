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
    
    // MARK: - Color Helper
    
    /// Safely convert SwiftUI Color to NSColor for use in attributed strings
    private func nsColor(from color: Color) -> NSColor {
        // Use NSColor directly from the Color
        // This is safer than NSColor(color) in some contexts
        return NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
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
        
        // Pre-compute colors to avoid repeated conversion
        let plainColor = nsColor(from: theme.plain)
        let lineNumberColor = nsColor(from: theme.lineNumber)
        
        // Paragraph style for line spacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        
        for (index, line) in lines.enumerated() {
            // Add line number if enabled
            if includeLineNumbers {
                let lineNumber = String(format: "%\(maxLineDigits)d  ", index + 1)
                let lineNumberAttrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: lineNumberColor,
                    .paragraphStyle: paragraphStyle.copy()
                ]
                result.append(NSAttributedString(string: lineNumber, attributes: lineNumberAttrs))
            }
            
            // Apply syntax highlighting to the line
            let tokens = highlighter.tokenize(line)
            
            if tokens.isEmpty {
                // No tokens, use plain text
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: plainColor,
                    .paragraphStyle: paragraphStyle.copy()
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
                            .foregroundColor: plainColor,
                            .paragraphStyle: paragraphStyle.copy()
                        ]
                        result.append(NSAttributedString(string: gap, attributes: attrs))
                    }
                    
                    // Add token
                    let tokenText = String(line[token.range])
                    let tokenColor = nsColor(from: theme.color(for: token.type))
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: tokenColor,
                        .paragraphStyle: paragraphStyle.copy()
                    ]
                    result.append(NSAttributedString(string: tokenText, attributes: attrs))
                    
                    lastEnd = token.range.upperBound
                }
                
                // Add any remaining text after last token
                if lastEnd < line.endIndex {
                    let remainder = String(line[lastEnd...])
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: plainColor,
                        .paragraphStyle: paragraphStyle.copy()
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
        
        // Page size (A4: 210mm x 297mm at 72 DPI)
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 36
        
        // Generate PDF data and write to file
        let pdfData = generatePDFData(attributedString: attributedString, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
        
        if pdfData.isEmpty {
            throw ExportError.pdfCreationFailed
        }
        
        try pdfData.write(to: url)
    }
    
    private func generatePDFData(attributedString: NSAttributedString, pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat) -> Data {
        let contentWidth = pageWidth - (margin * 2)
        
        // Use NSTextView's built-in PDF generation which handles coordinate systems correctly
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        
        // Force layout
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        
        // Create a text view sized to fit all content
        let textView = NSTextView(frame: NSRect(x: margin, y: margin, width: contentWidth, height: usedRect.height))
        textView.textStorage?.setAttributedString(attributedString)
        textView.backgroundColor = NSColor(theme.background)
        textView.drawsBackground = true
        
        // Create a container view with background that includes margins
        let containerHeight = usedRect.height + (margin * 2)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: containerHeight))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(theme.background).cgColor
        containerView.addSubview(textView)
        
        // Use dataWithPDF which handles all coordinate transforms correctly
        let pdfData = containerView.dataWithPDF(inside: containerView.bounds)
        
        return pdfData
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
        
        // Capture self strongly to keep exporter alive until export completes
        savePanel.begin { response in
            Swift.print("[PDF Export] Save panel response: \(response == .OK ? "OK" : "Cancelled")")
            if response == .OK, let url = savePanel.url {
                Swift.print("[PDF Export] Target URL: \(url.path)")
                do {
                    try self.exportToPDF(to: url)
                    // Verify file was created
                    if FileManager.default.fileExists(atPath: url.path) {
                        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                        let size = attrs?[.size] as? Int ?? 0
                        Swift.print("[PDF Export] SUCCESS - File created: \(url.path), size: \(size) bytes")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        Swift.print("[PDF Export] ERROR - File was not created at: \(url.path)")
                        self.showError("PDF file was not created. Please check permissions.")
                    }
                } catch {
                    Swift.print("[PDF Export] ERROR: \(error)")
                    self.showError("Failed to export PDF: \(error.localizedDescription)")
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
        
        // Capture self strongly to keep exporter alive until export completes
        savePanel.begin { response in
            Swift.print("[PNG Export] Save panel response: \(response == .OK ? "OK" : "Cancelled")")
            if response == .OK, let url = savePanel.url {
                Swift.print("[PNG Export] Target URL: \(url.path)")
                do {
                    try self.exportToPNG(to: url)
                    // Verify file was created
                    if FileManager.default.fileExists(atPath: url.path) {
                        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                        let size = attrs?[.size] as? Int ?? 0
                        Swift.print("[PNG Export] SUCCESS - File created: \(url.path), size: \(size) bytes")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        Swift.print("[PNG Export] ERROR - File was not created at: \(url.path)")
                        self.showError("PNG file was not created. Please check permissions.")
                    }
                } catch {
                    Swift.print("[PNG Export] ERROR: \(error)")
                    self.showError("Failed to export PNG: \(error.localizedDescription)")
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
