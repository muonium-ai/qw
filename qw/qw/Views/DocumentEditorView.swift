//
//  DocumentEditorView.swift
//  qw
//
//  Document editor view for editing text documents
//

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// The main document editor view
struct DocumentEditorView: View {
    @Binding var document: TextDocument
    var fileURL: URL?
    var initialReadOnly: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var fileType: SupportedFileType = .plainText
    @State private var isReadOnly: Bool = false
    @State private var isHexMode: Bool = false
    @State private var isImageMode: Bool = false
    @State private var isVideoMode: Bool = false
    @State private var isAudioMode: Bool = false
    @State private var isExecutableMode: Bool = false
    @State private var showBinaryAlert: Bool = false
    @StateObject private var searchState = SearchState()

    // Format mismatch warning (T-000063)
    @State private var mismatchResult: FormatMismatchDetector.MismatchResult?

    // Binary diff comparison state
    @State private var isComparing: Bool = false
    @State private var comparisonData: Data?
    @State private var comparisonName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Format mismatch warning banner (T-000063)
            mismatchBannerView

            // Search/Replace bar (hidden in hex mode)
            if searchState.isVisible && !isHexMode && !isImageMode {
                SearchReplaceView(
                    searchText: $searchState.searchText,
                    replaceText: $searchState.replaceText,
                    isVisible: $searchState.isVisible,
                    showReplace: $searchState.showReplace,
                    onFindNext: {
                        searchState.findNext()
                    },
                    onFindPrevious: {
                        searchState.findPrevious()
                    },
                    onReplace: {
                        if !isReadOnly {
                            searchState.replace(in: &document.text)
                        }
                    },
                    onReplaceAll: {
                        if !isReadOnly {
                            searchState.replaceAll(in: &document.text)
                        }
                    },
                    matchCount: searchState.matches.count,
                    currentMatchIndex: searchState.currentMatchIndex
                )
                .onChange(of: searchState.searchText) { _, _ in
                    searchState.findMatches(in: document.text)
                }
            }

            // Editor or Hex View
            mainContentView
        }
        #if os(macOS)
        .background(WindowTitleModeUpdater(isReadOnly: isReadOnly, isHexMode: isHexMode, isImageMode: isImageMode, isVideoMode: isVideoMode, isAudioMode: isAudioMode, isExecutableMode: isExecutableMode))
        #endif
        .onAppear {
            updateFileType()
            // Check if this file was opened in read-only mode from CLI
            if let url = fileURL {
                #if os(macOS)
                if ReadOnlyFileManager.shared.isWritable(url: url) {
                    isReadOnly = false
                } else if ReadOnlyFileManager.shared.isReadOnly(url: url) {
                    isReadOnly = true
                } else {
                    isReadOnly = initialReadOnly
                }
                #else
                isReadOnly = initialReadOnly
                #endif
            } else {
                // New untitled documents should start writable
                isReadOnly = false
            }

            // Auto-detect binary files: open images/videos/audio directly, prompt for others
            if document.isBinaryDetected {
                let detectedSignature = MagicBytes.detect(from: document.rawData)
                let detectedFormat = detectedSignature?.name

                // Determine category from DB if available (T-000063)
                let dbCategory: String? = {
                    let db = FormatDatabase.shared
                    guard db.isAvailable else { return nil }
                    return db.detectSignature(from: document.rawData)?.category
                }()

                // Check for extension vs content mismatch (T-000063)
                let mismatch = FormatMismatchDetector.check(
                    fileURL: fileURL,
                    detectedFormatName: detectedFormat,
                    detectedCategory: dbCategory
                )
                mismatchResult = mismatch

                // Critical mismatch with executable content: always show the binary
                // dialog so the user makes an explicit choice — never auto-route.
                let blockAutoRoute = mismatch?.severity == .critical
                    && FormatMismatchDetector.isExecutableFormat(name: detectedFormat ?? "")

                if blockAutoRoute {
                    showBinaryAlert = true
                    FormatLogger.logOpenFailure(fileURL: fileURL, formatName: detectedFormat, mode: "text", error: "Critical mismatch — executable disguised as \(mismatch?.extensionType ?? "unknown"); blocked auto-route")
                } else if isImageFile(data: document.rawData) {
                    isImageMode = true
                    FormatLogger.logOpenSuccess(fileURL: fileURL, formatName: detectedFormat, mode: "image")
                } else if isVideoFile(data: document.rawData) {
                    isVideoMode = true
                    FormatLogger.logOpenSuccess(fileURL: fileURL, formatName: detectedFormat, mode: "video")
                } else if isAudioFile(data: document.rawData) {
                    isAudioMode = true
                    FormatLogger.logOpenSuccess(fileURL: fileURL, formatName: detectedFormat, mode: "audio")
                } else {
                    showBinaryAlert = true
                    FormatLogger.logOpenFailure(fileURL: fileURL, formatName: detectedFormat, mode: "text", error: "Binary file detected, prompting user for mode selection")
                }
            }
        }
        .onChange(of: fileURL) { _, _ in
            updateFileType()
        }
        .confirmationDialog(
            "This file appears to be binary. How would you like to open it?",
            isPresented: $showBinaryAlert,
            titleVisibility: .visible
        ) {
            Button("Hex Mode") {
                isHexMode = true
            }
            if isImageFile(data: document.rawData) {
                Button("View Image") {
                    isImageMode = true
                }
            }
            if isVideoFile(data: document.rawData) {
                Button("Play Video") {
                    isVideoMode = true
                }
            }
            if isAudioFile(data: document.rawData) {
                Button("Play Audio") {
                    isAudioMode = true
                }
            }
            if isExecutableFile(data: document.rawData) {
                Button("Run in Sandbox") {
                    isExecutableMode = true
                    let detectedFormat = MagicBytes.detect(from: document.rawData)?.name
                    FormatLogger.logOpenSuccess(fileURL: fileURL, formatName: detectedFormat, mode: "executable")
                }
            }
            #if os(macOS)
            if let url = fileURL {
                Button("Preview (Quick Look)") {
                    showQuickLookPreview(for: url)
                }
                Button("Open in Default App") {
                    NSWorkspace.shared.open(url)
                }
            }
            #endif
            Button("Cancel", role: .cancel) {
                isHexMode = true
            }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { searchState.isVisible.toggle() }) {
                    Image(systemName: "magnifyingglass")
                }
                .help("Find (⌘F)")
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityIdentifier("toggleSearchButton")
            }
        }
        #endif
        .focusedSceneValue(\.searchState, searchState)
        #if os(macOS)
        .focusedSceneValue(\.documentExportAction, { exportDocument() })
        .focusedSceneValue(\.documentPrintAction, { printDocument() })
        .focusedSceneValue(\.documentExportPDFAction, { exportAsPDF() })
        .focusedSceneValue(\.documentExportPNGAction, { exportAsPNG() })
        .focusedSceneValue(\.toggleReadOnlyAction, { isReadOnly.toggle() })
        .focusedSceneValue(\.isReadOnly, isReadOnly)
        .focusedSceneValue(\.toggleHexModeAction, { isHexMode.toggle() })
        .focusedSceneValue(\.isHexMode, isHexMode)
        .focusedSceneValue(\.hexCompareAction, { openComparePanel() })
        .optionalFocusedSceneValue(\.currentFileURL, fileURL)
        #endif
    }

        #if os(macOS)
        private struct WindowTitleModeUpdater: NSViewRepresentable {
            let isReadOnly: Bool
            let isHexMode: Bool
            let isImageMode: Bool
            let isVideoMode: Bool
            let isAudioMode: Bool
            let isExecutableMode: Bool

            func makeNSView(context: Context) -> NSView {
                let view = NSView(frame: .zero)
                DispatchQueue.main.async {
                    updateWindowTitle(for: view.window)
                }
                return view
            }

            func updateNSView(_ nsView: NSView, context: Context) {
                DispatchQueue.main.async {
                    updateWindowTitle(for: nsView.window)
                }
            }

            private func updateWindowTitle(for window: NSWindow?) {
                guard let window = window else { return }
                var modeText = isReadOnly ? "Read Only" : "Write"
                if isHexMode {
                    modeText = "Hex — \(modeText)"
                } else if isImageMode {
                    modeText = "Image"
                } else if isVideoMode {
                    modeText = "Video"
                } else if isAudioMode {
                    modeText = "Audio"
                } else if isExecutableMode {
                    modeText = "Executable"
                }
                if #available(macOS 11.0, *) {
                    window.subtitle = modeText
                } else {
                    let baseTitle = stripModeSuffix(from: window.title)
                    window.title = "\(baseTitle) — \(modeText)"
                }
            }

            private func stripModeSuffix(from title: String) -> String {
                let suffixes = [" — Read Only", " — Write", " — Hex — Read Only", " — Hex — Write", " — Image", " — Video", " — Audio", " — Executable"]
                for suffix in suffixes where title.hasSuffix(suffix) {
                    return String(title.dropLast(suffix.count))
                }
                return title
            }
        }
        #endif

    #if os(macOS)
    private func showQuickLookPreview(for url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", url.path]
        // Suppress qlmanage's stdout/stderr chatter
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func openComparePanel() {
        guard isHexMode else {
            NSSound.beep()
            return
        }
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.message = "Select a file to compare with"
        openPanel.prompt = "Compare"

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    comparisonData = data
                    comparisonName = url.lastPathComponent
                    isComparing = true
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Compare Error"
                    alert.informativeText = "Failed to read file: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    #endif

    // MARK: - Mismatch banner (T-000063)

    @ViewBuilder
    private var mismatchBannerView: some View {
        if let mismatch = mismatchResult {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(mismatch.severity == .critical ? .red : .yellow)
                Text(mismatch.message)
                    .font(.caption)
                Spacer()
                Button("Dismiss") { mismatchResult = nil }
                    .buttonStyle(.plain)
            }
            .padding(8)
            .background(mismatch.severity == .critical ? Color.red.opacity(0.15) : Color.yellow.opacity(0.15))
        }
    }

    // MARK: - Main content view (extracted to help the type-checker)

    @ViewBuilder
    private var mainContentView: some View {
        if isHexMode && isComparing, let compData = comparisonData {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Close Comparison") {
                        isComparing = false
                        comparisonData = nil
                        comparisonName = ""
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .background {
                    #if os(macOS)
                    Color(nsColor: .windowBackgroundColor)
                    #else
                    Color(uiColor: .secondarySystemBackground)
                    #endif
                }
                HexDiffView(
                    dataA: document.rawData,
                    dataB: compData,
                    nameA: fileURL?.lastPathComponent ?? "Current File",
                    nameB: comparisonName
                )
            }
            .accessibilityIdentifier("hexDiffViewer")
        } else if isHexMode {
            HexView(data: document.rawData, fileURL: fileURL)
                .accessibilityIdentifier("hexViewer")
        } else if isImageMode && document.isBinaryDetected {
            ImageViewerView(
                data: document.rawData,
                fileURL: fileURL,
                onSwitchToHex: { switchToHexMode() },
                onOpenExternal: fileURL.map { url in { openInDefaultApp(url: url) } }
            )
            .accessibilityIdentifier("imageViewer")
        } else if isVideoMode && document.isBinaryDetected, let url = fileURL {
            videoPlayerContent(url: url)
        } else if isAudioMode && document.isBinaryDetected, let url = fileURL {
            audioPlayerContent(url: url)
        } else if isExecutableMode && document.isBinaryDetected, let url = fileURL {
            executableRunnerContent(url: url)
        } else {
            CodeEditorView(
                text: $document.text,
                fileType: fileType,
                fileName: fileURL?.lastPathComponent,
                isReadOnly: isReadOnly,
                searchState: searchState
            )
            .accessibilityIdentifier("documentEditor")
        }
    }

    /// Returns `true` when the data's magic bytes indicate an image format.
    private func isImageFile(data: Data) -> Bool {
        guard let sig = MagicBytes.detect(from: data) else { return false }
        let imageKeywords = ["PNG", "JPEG", "GIF", "BMP", "TIFF", "WebP", "ICO"]
        return imageKeywords.contains(where: { sig.name.contains($0) })
    }

    /// Returns the video player view (macOS only, text fallback elsewhere).
    @ViewBuilder
    private func videoPlayerContent(url: URL) -> some View {
        #if os(macOS)
        VideoPlayerView(
            fileURL: url,
            onSwitchToHex: { switchToHexMode() },
            onOpenExternal: { NSWorkspace.shared.open(url) }
        )
        .accessibilityIdentifier("videoPlayer")
        #else
        Text("Video playback is not supported on this platform.")
            .foregroundColor(.secondary)
        #endif
    }

    /// Returns `true` when the data's magic bytes indicate a video format.
    private func isVideoFile(data: Data) -> Bool {
        guard let sig = MagicBytes.detect(from: data) else { return false }
        let name = sig.name.lowercased()
        let videoKeywords = ["mp4", "video", "avi", "mkv", "webm", "mov", "flv", "mpeg", "matroska"]
        return videoKeywords.contains(where: { name.contains($0) })
    }

    /// Returns the audio player view (macOS only, text fallback elsewhere).
    @ViewBuilder
    private func audioPlayerContent(url: URL) -> some View {
        #if os(macOS)
        AudioPlayerView(
            fileURL: url,
            onSwitchToHex: { switchToHexMode() },
            onOpenExternal: { NSWorkspace.shared.open(url) }
        )
        .accessibilityIdentifier("audioPlayer")
        #else
        Text("Audio playback is not supported on this platform.")
            .foregroundColor(.secondary)
        #endif
    }

    /// Returns `true` when the data's magic bytes indicate an audio-only format.
    private func isAudioFile(data: Data) -> Bool {
        guard let sig = MagicBytes.detect(from: data) else { return false }
        let name = sig.name
        // RIFF can be WAV or AVI — only treat as audio when it is not also video
        if isVideoFile(data: data) { return false }
        let audioKeywords = ["WAV", "RIFF", "MP3", "FLAC", "OGG", "AAC", "M4A", "AIFF", "MIDI", "Audio", "Opus"]
        return audioKeywords.contains(where: { name.contains($0) })
    }

    /// Returns `true` when the data's magic bytes indicate an executable format (WASM only for now).
    private func isExecutableFile(data: Data) -> Bool {
        guard let sig = MagicBytes.detect(from: data) else { return false }
        return sig.name.contains("WebAssembly")
    }

    /// Executable runner view with WasmRunner integration.
    @ViewBuilder
    private func executableRunnerContent(url: URL) -> some View {
        #if os(macOS)
        WasmExecutionView(
            fileURL: url,
            rawData: document.rawData,
            onSwitchToHex: { switchToHexMode() }
        )
        .accessibilityIdentifier("executableRunner")
        #else
        Text("Executable running is not supported on this platform.")
            .foregroundColor(.secondary)
        #endif
    }

    /// Switches to hex mode from any media viewer.
    private func switchToHexMode() {
        isImageMode = false
        isVideoMode = false
        isAudioMode = false
        isExecutableMode = false
        isHexMode = true
    }

    /// Opens the given URL in the system default app.
    private func openInDefaultApp(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func updateFileType() {
        if let url = fileURL {
            fileType = SupportedFileType.from(url: url)
        } else {
            fileType = document.fileType
        }
    }

    #if os(macOS)
    private func exportDocument() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = TextDocument.writableContentTypes
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save As"
        savePanel.message = "Choose a location to save your file"
        savePanel.nameFieldLabel = "File Name:"

        // Set default filename from current file or use "Untitled"
        if let url = fileURL {
            savePanel.nameFieldStringValue = url.lastPathComponent
        } else {
            savePanel.nameFieldStringValue = "Untitled.\(fileType.rawValue)"
        }

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let data = document.text.data(using: .utf8) ?? Data()
                    try data.write(to: url)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Export Error"
                    alert.informativeText = "Failed to save file: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    private func printDocument() {
        let settings = EditorSettingsManager.shared
        let exporter = DocumentExporter(
            text: document.text,
            fileType: fileType,
            fileName: fileURL?.lastPathComponent,
            theme: settings.syntaxTheme(for: .light), // Intentionally light: prints on paper are most legible with a light background
            includeLineNumbers: settings.showLineNumbers,
            fontSize: settings.fontSize,
            fontName: settings.selectedFont.fontName
        )
        exporter.printDocument()
    }

    private func exportAsPDF() {
        let settings = EditorSettingsManager.shared
        let exporter = DocumentExporter(
            text: document.text,
            fileType: fileType,
            fileName: fileURL?.lastPathComponent,
            theme: settings.syntaxTheme(for: colorScheme),
            includeLineNumbers: settings.showLineNumbers,
            fontSize: settings.fontSize,
            fontName: settings.selectedFont.fontName
        )

        let defaultName = fileURL?.lastPathComponent ?? "Untitled"
        exporter.showPDFExportDialog(defaultName: defaultName)
    }

    private func exportAsPNG() {
        let settings = EditorSettingsManager.shared
        let exporter = DocumentExporter(
            text: document.text,
            fileType: fileType,
            fileName: fileURL?.lastPathComponent,
            theme: settings.syntaxTheme(for: colorScheme),
            includeLineNumbers: settings.showLineNumbers,
            fontSize: settings.fontSize,
            fontName: settings.selectedFont.fontName
        )

        let defaultName = fileURL?.lastPathComponent ?? "Untitled"
        exporter.showPNGExportDialog(defaultName: defaultName)
    }
    #endif
}

// MARK: - Focus Values for Search State
struct SearchStateFocusKey: FocusedValueKey {
    typealias Value = SearchState
}

// MARK: - Focus Values for Document Actions (Print/Export)
struct DocumentPrintActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DocumentExportActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DocumentExportPDFActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DocumentExportPNGActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ToggleReadOnlyActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct IsReadOnlyFocusKey: FocusedValueKey {
    typealias Value = Bool
}

struct ToggleHexModeActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct IsHexModeFocusKey: FocusedValueKey {
    typealias Value = Bool
}

struct HexCompareActionFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct CurrentFileURLFocusKey: FocusedValueKey {
    typealias Value = URL
}

extension FocusedValues {
    var searchState: SearchState? {
        get { self[SearchStateFocusKey.self] }
        set { self[SearchStateFocusKey.self] = newValue }
    }

    var documentPrintAction: (() -> Void)? {
        get { self[DocumentPrintActionFocusKey.self] }
        set { self[DocumentPrintActionFocusKey.self] = newValue }
    }

    var documentExportAction: (() -> Void)? {
        get { self[DocumentExportActionFocusKey.self] }
        set { self[DocumentExportActionFocusKey.self] = newValue }
    }

    var documentExportPDFAction: (() -> Void)? {
        get { self[DocumentExportPDFActionFocusKey.self] }
        set { self[DocumentExportPDFActionFocusKey.self] = newValue }
    }

    var documentExportPNGAction: (() -> Void)? {
        get { self[DocumentExportPNGActionFocusKey.self] }
        set { self[DocumentExportPNGActionFocusKey.self] = newValue }
    }

    var toggleReadOnlyAction: (() -> Void)? {
        get { self[ToggleReadOnlyActionFocusKey.self] }
        set { self[ToggleReadOnlyActionFocusKey.self] = newValue }
    }

    var isReadOnly: Bool? {
        get { self[IsReadOnlyFocusKey.self] }
        set { self[IsReadOnlyFocusKey.self] = newValue }
    }

    var toggleHexModeAction: (() -> Void)? {
        get { self[ToggleHexModeActionFocusKey.self] }
        set { self[ToggleHexModeActionFocusKey.self] = newValue }
    }

    var isHexMode: Bool? {
        get { self[IsHexModeFocusKey.self] }
        set { self[IsHexModeFocusKey.self] = newValue }
    }

    var hexCompareAction: (() -> Void)? {
        get { self[HexCompareActionFocusKey.self] }
        set { self[HexCompareActionFocusKey.self] = newValue }
    }

    var currentFileURL: URL? {
        get { self[CurrentFileURLFocusKey.self] }
        set { self[CurrentFileURLFocusKey.self] = newValue }
    }
}

// MARK: - Optional Focused Scene Value Helper
extension View {
    /// Conditionally sets a focused scene value only when the optional value is non-nil.
    @ViewBuilder
    func optionalFocusedSceneValue<T>(_ keyPath: WritableKeyPath<FocusedValues, T?>, _ value: T?) -> some View {
        if let value = value {
            self.focusedSceneValue(keyPath, value)
        } else {
            self
        }
    }
}

#Preview {
    DocumentEditorView(
        document: .constant(TextDocument(text: "Hello, World!", fileType: .plainText)),
        fileURL: nil
    )
}
