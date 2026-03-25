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
    private let fileName: String?
    private let theme: SyntaxTheme
    private let includeLineNumbers: Bool
    private let fontSize: CGFloat
    private let fontName: String
    
    // MARK: - Initialization
    
    init(
        text: String,
        fileType: SupportedFileType,
        fileName: String? = nil,
        theme: SyntaxTheme,
        includeLineNumbers: Bool,
        fontSize: CGFloat = 12,
        fontName: String = "Menlo"
    ) {
        self.text = text
        self.fileType = fileType
        self.fileName = fileName
        self.theme = theme
        self.includeLineNumbers = includeLineNumbers
        self.fontSize = fontSize
        self.fontName = fontName
    }
    
    // MARK: - Convenience initializer from settings
    
    convenience init(text: String, fileType: SupportedFileType, fileName: String? = nil, colorScheme: ColorScheme) {
        let settings = EditorSettingsManager.shared
        let theme = settings.syntaxTheme(for: colorScheme)
        
        self.init(
            text: text,
            fileType: fileType,
            fileName: fileName,
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
    
    private func createAttributedString(includeLineNumbers: Bool? = nil) -> NSAttributedString {
        let includeLineNumbers = includeLineNumbers ?? self.includeLineNumbers
        let lines = text.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        let highlighter = SyntaxHighlighter(fileType: fileType, theme: theme, fileName: fileName)
        let font = getFont()
        
        // Calculate line number width based on max digits needed
        let lineCount = lines.count
        let maxLineDigits = String(lineCount).count
        // Estimate width: each digit ~7pt at 12pt font, plus 2 spaces padding
        let lineNumberWidth: CGFloat = includeLineNumbers ? CGFloat(maxLineDigits + 2) * (fontSize * 0.6) : 0
        
        // Pre-compute colors to avoid repeated conversion
        let plainColor = nsColor(from: theme.plain)
        let lineNumberColor = nsColor(from: theme.lineNumber)
        
        // Paragraph style for line spacing and proper wrapping
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        // Set headIndent so wrapped lines start after line number area
        if includeLineNumbers {
            paragraphStyle.headIndent = lineNumberWidth
        }

        if !includeLineNumbers {
            // Build attributed string using full-text tokenization (pygments-swift)
            let full = NSMutableAttributedString(string: text)
            full.addAttributes([
                .font: font,
                .foregroundColor: plainColor,
                .paragraphStyle: paragraphStyle
            ], range: NSRange(location: 0, length: (text as NSString).length))

            let tokens = highlighter.tokenize(text)
            for token in tokens {
                let nsRange = NSRange(token.range, in: text)
                if nsRange.location != NSNotFound && nsRange.location + nsRange.length <= (text as NSString).length {
                    full.addAttributes([
                        .foregroundColor: nsColor(from: theme.color(for: token.type))
                    ], range: nsRange)
                }
            }

            return full
        }
        
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
    
    func printDocument() {
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
        let attributedString = createAttributedString(includeLineNumbers: false)
        let options = RenderOptions(
            width: nil,
            padding: 18,
            background: nsColor(from: theme.background),
            foreground: nsColor(from: theme.plain)
        )

        let pdfData = CodeRender.renderPDF(attributed: attributedString, options: options)
        if pdfData.isEmpty {
            throw ExportError.pdfCreationFailed
        }

        try pdfData.write(to: url, options: .atomic)
    }
    
    // MARK: - Export to PNG
    
    func exportToPNG(to url: URL) throws {
        let attributedString = createAttributedString(includeLineNumbers: false)
        let options = RenderOptions(
            width: nil,
            padding: 18,
            background: nsColor(from: theme.background),
            foreground: nsColor(from: theme.plain)
        )

        do {
            let pngData = try CodeRender.renderPNG(attributed: attributedString, options: options, scale: 2.0)
            try pngData.write(to: url, options: .atomic)
        } catch {
            throw ExportError.pngCreationFailed
        }
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
        let normalizedName = defaultName.lowercased().hasSuffix(".pdf")
            ? defaultName
            : "\(defaultName).pdf"
        savePanel.nameFieldStringValue = normalizedName
        
        // Capture self strongly to keep exporter alive until export completes
        savePanel.begin { response in
            print("[PDF Export] Save panel response: \(response == .OK ? "OK" : "Cancelled")")
            if response == .OK, let url = savePanel.url {
                print("[PDF Export] Target URL: \(url.path)")
                do {
                    try self.exportToPDF(to: url)
                    // Verify file was created
                    if FileManager.default.fileExists(atPath: url.path) {
                        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                        let size = attrs?[.size] as? Int ?? 0
                        print("[PDF Export] SUCCESS - File created: \(url.path), size: \(size) bytes")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        print("[PDF Export] ERROR - File was not created at: \(url.path)")
                        self.showError("PDF file was not created. Please check permissions.")
                    }
                } catch {
                    print("[PDF Export] ERROR: \(error)")
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
        let normalizedName = defaultName.lowercased().hasSuffix(".png")
            ? defaultName
            : "\(defaultName).png"
        savePanel.nameFieldStringValue = normalizedName
        
        // Capture self strongly to keep exporter alive until export completes
        savePanel.begin { response in
            print("[PNG Export] Save panel response: \(response == .OK ? "OK" : "Cancelled")")
            if response == .OK, let url = savePanel.url {
                print("[PNG Export] Target URL: \(url.path)")
                do {
                    try self.exportToPNG(to: url)
                    // Verify file was created
                    if FileManager.default.fileExists(atPath: url.path) {
                        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                        let size = attrs?[.size] as? Int ?? 0
                        print("[PNG Export] SUCCESS - File created: \(url.path), size: \(size) bytes")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        print("[PNG Export] ERROR - File was not created at: \(url.path)")
                        self.showError("PNG file was not created. Please check permissions.")
                    }
                } catch {
                    print("[PNG Export] ERROR: \(error)")
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
        includeLineNumbers: Bool? = nil,
        theme: SyntaxTheme? = nil,
        fontSize: CGFloat? = nil
    ) throws {
        // Read input file
        let inputURL = URL(fileURLWithPath: inputPath)
        let text = try String(contentsOf: inputURL, encoding: .utf8)
        let fileType = SupportedFileType.from(url: inputURL)

        // Read settings from EditorSettingsManager
        let settings = EditorSettingsManager.shared

        // Create exporter using user settings (with optional overrides)
        let exporter = DocumentExporter(
            text: text,
            fileType: fileType,
            fileName: inputURL.lastPathComponent,
            theme: theme ?? settings.syntaxTheme(for: .dark),
            includeLineNumbers: includeLineNumbers ?? settings.showLineNumbers,
            fontSize: fontSize ?? settings.fontSize,
            fontName: settings.selectedFont.fontName
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
        includeLineNumbers: Bool? = nil,
        theme: SyntaxTheme? = nil,
        fontSize: CGFloat? = nil
    ) throws {
        // Read input file
        let inputURL = URL(fileURLWithPath: inputPath)
        let text = try String(contentsOf: inputURL, encoding: .utf8)
        let fileType = SupportedFileType.from(url: inputURL)

        // Read settings from EditorSettingsManager
        let settings = EditorSettingsManager.shared

        // Create exporter using user settings (with optional overrides)
        let exporter = DocumentExporter(
            text: text,
            fileType: fileType,
            fileName: inputURL.lastPathComponent,
            theme: theme ?? settings.syntaxTheme(for: .dark),
            includeLineNumbers: includeLineNumbers ?? settings.showLineNumbers,
            fontSize: fontSize ?? settings.fontSize,
            fontName: settings.selectedFont.fontName
        )
        
        exporter.printDocument()
    }
}

#endif
