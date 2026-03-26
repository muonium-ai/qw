//
//  HexView.swift
//  qw
//
//  Hex viewer and editor displaying file contents in canonical hex dump format.
//  Supports byte selection, copy/export in multiple formats, and inline editing.
//  Ticket: T-000019, T-000020, T-000023, T-000024, T-000025, T-000026
//

import SwiftUI

/// A row of hex dump output: offset, 16 bytes of hex, and ASCII representation.
/// Computed lazily from a Data slice — no intermediate [UInt8] array needed.
private struct HexRow: Identifiable {
    let id: Int // row index (stable ID for LazyVStack)
    let offset: Int
    let bytes: Data.SubSequence
}

/// Hex viewer/editor displaying Data in canonical hex dump format.
///
/// Layout per row:
///   `00000010  48 65 6c 6c 6f 20 57 6f  72 6c 64 21 0a 00 00 00  |Hello World!....|`
///
/// - Three columns: offset gutter, hex bytes (16 per row with wider gap after byte 8), ASCII sidebar.
/// - Non-printable bytes render as `.` in the ASCII column.
/// - Null bytes are dimmed, high bytes (>127) use the accent color, printable ASCII uses the default color.
/// - Alternating row backgrounds for readability.
/// - Click to select a byte, shift-click to extend selection.
/// - Right-click to copy selection as Hex String, C Array, Swift Array, Raw Bytes, or Hex Dump.
/// - Cmd+C copies selected bytes as a hex string.
/// - Status bar showing total file size and selection info.
///
/// **Virtual scrolling**: rows are computed lazily via `LazyVStack` and `ForEach`
/// over an index range. Only the bytes for visible rows are accessed, keeping
/// memory usage constant regardless of file size.
///
/// **Memory-mapped I/O**: use `HexView(url:)` to open large files with
/// `Data(contentsOf:options:.mappedIfSafe)` so the OS pages in only the
/// portions that are actually read.
///
/// **Two modes**:
/// - **Read-only**: `HexView(data:)` or `HexView(url:)` — selection + copy only.
/// - **Editable**: `HexView(hexDocument:)` — type hex digits to overwrite bytes,
///   delete key removes byte, insert via toolbar/keyboard. Full undo/redo.
struct HexView: View {

    // MARK: - Stored properties

    /// Read-only data — used when `hexDocument` is not provided.
    private let readOnlyData: Data?

    /// Optional file URL — needed for ffprobe metadata extraction.
    private let fileURL: URL?

    /// Editable document model — nil in read-only mode.
    @ObservedObject private var hexDocumentStorage: HexDocument

    /// Whether this view supports editing.
    private let isEditable: Bool

    // MARK: - Selection state

    @State private var selectionStart: Int?
    @State private var selectionEnd: Int?

    /// Whether the ASCII pane is the active input target (vs. the hex pane).
    @State private var asciiInputMode: Bool = false

    /// Accumulator for the first hex nibble when typing a two-digit hex value.
    @State private var pendingNibble: UInt8?

    @Environment(\.undoManager) private var environmentUndoManager

    // MARK: - Hex search state

    @StateObject private var hexSearchState = HexSearchState()

    // MARK: - File layout sections (cached)

    /// Cached file sections detected from the binary layout.
    /// Uses a class wrapper so the computation is performed once per data identity,
    /// not on every view redraw.
    @State private var cachedSections: [FileSection] = []
    @State private var cachedSectionsDataCount: Int = -1

    // MARK: - Data inspector state

    @State private var showDataInspector: Bool = true
    @State private var isLittleEndian: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    /// Current editor theme, derived from user settings and system color scheme.
    private var theme: SyntaxTheme {
        EditorSettingsManager.shared.syntaxTheme(for: colorScheme)
    }

    // MARK: - Annotation state

    @State private var showAnnotationPanel: Bool = false
    @State private var cachedAnnotations: [FieldValue] = []
    @State private var cachedAnnotationsDataCount: Int = -1

    // MARK: - EXIF metadata state

    @State private var cachedExifMetadata: ExifMetadata = ExifMetadata(entries: [])
    @State private var cachedExifDataCount: Int = -1

    // MARK: - FFprobe metadata state

    @State private var ffprobeResult: FFprobeResult?
    @State private var ffprobeTask: Task<Void, Never>?
    @State private var showMediaMetadata: Bool = false

    /// The normalized (ordered) range of selected byte indices, if any.
    private var selectionRange: ClosedRange<Int>? {
        guard let s = selectionStart, let e = selectionEnd else { return nil }
        return min(s, e)...max(s, e)
    }

    /// The selected bytes as `Data`, if a selection exists.
    var selectedData: Data? {
        let d = displayData
        guard let range = selectionRange, !d.isEmpty else { return nil }
        let clamped = range.clamped(to: 0...(d.count - 1))
        guard !clamped.isEmpty else { return nil }
        let dataStart = d.startIndex + clamped.lowerBound
        let dataEnd = d.startIndex + clamped.upperBound + 1
        return Data(d[dataStart..<dataEnd])
    }

    // MARK: - Initializers

    /// Opens a file with memory-mapped I/O (`mappedIfSafe`). Read-only.
    init(url: URL) {
        self.readOnlyData = (try? Data(contentsOf: url, options: .mappedIfSafe)) ?? Data()
        self.fileURL = url
        self._hexDocumentStorage = ObservedObject(wrappedValue: HexDocument(data: Data()))
        self.isEditable = false
    }

    /// Standard read-only initializer for in-memory data.
    init(data: Data, fileURL: URL? = nil) {
        self.readOnlyData = data
        self.fileURL = fileURL
        self._hexDocumentStorage = ObservedObject(wrappedValue: HexDocument(data: Data()))
        self.isEditable = false
    }

    /// Editable initializer — full editing support with undo/redo.
    init(hexDocument: HexDocument, fileURL: URL? = nil) {
        self.readOnlyData = nil
        self.fileURL = fileURL
        self._hexDocumentStorage = ObservedObject(wrappedValue: hexDocument)
        self.isEditable = true
    }

    // MARK: - Computed

    /// The data to display.
    private var displayData: Data {
        isEditable ? hexDocumentStorage.currentData : (readOnlyData ?? Data())
    }

    /// Whether the current file is detected as audio/video.
    private var isMediaFile: Bool {
        let data = displayData
        if let sig = MagicBytes.detect(from: data),
           FFprobeService.isAudioVideoFormat(signatureName: sig.name) {
            return true
        }
        if let dbSig = FormatDatabase.shared.detectSignature(from: data),
           FFprobeService.isAudioVideoCategory(dbSig.category) ||
           FFprobeService.isAudioVideoFormat(signatureName: dbSig.name) {
            return true
        }
        return false
    }

    /// Total number of 16-byte rows needed to display the data.
    private var rowCount: Int {
        max((displayData.count + 15) / 16, 0)
    }

    /// Build a single `HexRow` on demand.
    private func row(at index: Int) -> HexRow {
        let d = displayData
        let start = d.startIndex + index * 16
        let end = min(start + 16, d.endIndex)
        return HexRow(id: index, offset: index * 16, bytes: d[start..<end])
    }

    private var fileSizeDescription: String {
        let count = displayData.count
        if count == 0 {
            return "0 bytes"
        } else if count == 1 {
            return "1 byte"
        } else if count < 1024 {
            return "\(count) bytes"
        } else if count < 1024 * 1024 {
            return String(format: "%.1f KB (%d bytes)", Double(count) / 1024.0, count)
        } else {
            return String(format: "%.1f MB (%d bytes)", Double(count) / (1024.0 * 1024.0), count)
        }
    }

    private var selectionDescription: String? {
        guard let range = selectionRange else { return nil }
        let count = range.count
        if isEditable && count == 1 {
            let idx = range.lowerBound
            let d = displayData
            if idx < d.count {
                let byte = d[d.startIndex + idx]
                return String(format: "Offset: 0x%X  Value: 0x%02X (%d)", idx, byte, byte)
            }
        }
        let label = count == 1 ? "1 byte" : "\(count) bytes"
        return "Selection: \(String(format: "0x%X", range.lowerBound))\u{2013}\(String(format: "0x%X", range.upperBound)) (\(label))"
    }

    /// Recompute field annotations if data has changed.
    private func updateAnnotationsIfNeeded() {
        let count = displayData.count
        if count != cachedAnnotationsDataCount {
            cachedAnnotationsDataCount = count
            cachedAnnotations = FileAnnotator.annotate(data: displayData)
        }
    }

    /// Recompute EXIF metadata if data has changed.
    /// Only parses for image formats (JPEG, PNG) to avoid unnecessary work.
    private func updateExifIfNeeded() {
        let count = displayData.count
        if count != cachedExifDataCount {
            cachedExifDataCount = count
            if let sig = MagicBytes.detect(from: displayData),
               sig.name == "JPEG Image" || sig.name == "PNG Image" {
                cachedExifMetadata = ExifParser.parse(data: displayData)
            } else {
                cachedExifMetadata = ExifMetadata(entries: [])
            }
        }
    }

    /// Tooltip for a byte from field annotations, if any.
    private func annotationTooltip(for index: Int) -> String? {
        FileAnnotator.tooltip(for: index, in: cachedAnnotations)
    }

    /// Determine if the current file is audio/video and invoke ffprobe if so.
    private func triggerFFprobeIfNeeded() {
        guard let url = fileURL else { return }
        guard ffprobeResult == nil else { return } // already probed

        let data = displayData
        // Check hardcoded magic bytes
        let isMedia: Bool
        if let sig = MagicBytes.detect(from: data),
           FFprobeService.isAudioVideoFormat(signatureName: sig.name) {
            isMedia = true
        } else if let dbSig = FormatDatabase.shared.detectSignature(from: data),
                  FFprobeService.isAudioVideoCategory(dbSig.category) ||
                  FFprobeService.isAudioVideoFormat(signatureName: dbSig.name) {
            isMedia = true
        } else {
            isMedia = false
        }

        guard isMedia else { return }

        showMediaMetadata = true
        ffprobeTask?.cancel()
        ffprobeTask = Task {
            let result = await FFprobeService.probe(fileURL: url)
            if !Task.isCancelled {
                await MainActor.run {
                    ffprobeResult = result
                }
            }
        }
    }

    /// Recompute file sections if data has changed.
    private func updateSectionsIfNeeded() {
        let count = displayData.count
        if count != cachedSectionsDataCount {
            cachedSectionsDataCount = count
            cachedSections = FileLayoutDetector.detect(data: displayData)
        }
    }

    /// Find the section that contains the given byte index, if any.
    private func sectionForByte(at index: Int) -> FileSection? {
        cachedSections.first { $0.range.contains(index) }
    }

    /// Background color for a byte based on its file section, or `.clear`.
    private func sectionBackground(for index: Int) -> Color {
        guard let section = sectionForByte(at: index) else { return .clear }
        let color = section.kind.color
        return color == .clear ? .clear : color.opacity(0.15)
    }

    /// Tooltip text for a byte based on its file section, or nil.
    private func sectionTooltip(for index: Int) -> String? {
        guard let section = sectionForByte(at: index) else { return nil }
        return "\(section.name): \(section.description)"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if hexSearchState.isVisible {
                HexSearchView(
                    state: hexSearchState,
                    data: displayData,
                    hexDocument: isEditable ? hexDocumentStorage : nil
                )
            }
            if hexSearchState.isGoToOffsetVisible {
                GoToOffsetView(
                    isPresented: $hexSearchState.isGoToOffsetVisible,
                    dataCount: displayData.count
                ) { offset in
                    selectionStart = offset
                    selectionEnd = offset
                }
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if displayData.isEmpty {
                        emptyView
                    } else {
                        hexContent
                    }
                    statusBar
                    if !cachedSections.isEmpty {
                        sectionLegendView
                    }
                }
                if showDataInspector && selectionStart != nil {
                    Divider()
                    DataInspectorView(
                        data: displayData,
                        cursorOffset: selectionStart,
                        isLittleEndian: $isLittleEndian
                    )
                }
                if showAnnotationPanel {
                    Divider()
                    AnnotationPanelView(annotations: cachedAnnotations, exifMetadata: cachedExifMetadata)
                }
                if showMediaMetadata {
                    Divider()
                    MediaMetadataPanel(result: ffprobeResult)
                }
            }
        }
        #if os(macOS)
        .onCopyCommand {
            guard let sel = selectedData else { return [] }
            let text = HexFormatter.formatAsHexString(sel)
            let item = NSItemProvider(object: text as NSString)
            return [item]
        }
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    hexSearchState.isVisible.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Find in hex")

                Button {
                    hexSearchState.isGoToOffsetVisible.toggle()
                } label: {
                    Image(systemName: "arrow.right.to.line")
                }
                .help("Go to offset")

                Button {
                    showDataInspector.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .help("Toggle Data Inspector")

                Button {
                    showAnnotationPanel.toggle()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .help("Toggle Format Annotations")

                if isMediaFile {
                    Button {
                        showMediaMetadata.toggle()
                        if showMediaMetadata {
                            triggerFFprobeIfNeeded()
                        }
                    } label: {
                        Image(systemName: "film")
                    }
                    .help("Toggle Media Metadata (ffprobe)")
                }
            }
        }
        .onAppear {
            if isEditable {
                hexDocumentStorage.undoManager = environmentUndoManager
            }
            updateSectionsIfNeeded()
            updateAnnotationsIfNeeded()
            updateExifIfNeeded()
            triggerFFprobeIfNeeded()
        }
        .onChange(of: environmentUndoManager) { _, newValue in
            if isEditable {
                hexDocumentStorage.undoManager = newValue
            }
        }
        .onChange(of: displayData.count) { _, _ in
            updateSectionsIfNeeded()
            updateAnnotationsIfNeeded()
            updateExifIfNeeded()
        }
    }

    // MARK: - Subviews

    private var emptyView: some View {
        VStack {
            Spacer()
            Text("Empty file")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(theme.comment)
            if isEditable {
                Button("Insert Byte") {
                    hexDocumentStorage.insertByte(0x00, at: 0)
                    selectionStart = 0
                    selectionEnd = 0
                }
                .padding(.top, 8)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    private var hexContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rowCount, id: \.self) { index in
                        let r = row(at: index)
                        hexRowView(r)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(index.isMultiple(of: 2) ? Color.clear : alternateRowBackground)
                            .id(index)
                    }
                }
            }
            .onChange(of: hexSearchState.currentMatchIndex) { _, newIndex in
                guard !hexSearchState.matches.isEmpty, newIndex < hexSearchState.matches.count else { return }
                let matchStart = hexSearchState.matches[newIndex].lowerBound
                let targetRow = matchStart / 16
                withAnimation {
                    proxy.scrollTo(targetRow, anchor: .center)
                }
            }
            .onChange(of: selectionStart) { _, newValue in
                guard let offset = newValue else { return }
                let targetRow = offset / 16
                withAnimation {
                    proxy.scrollTo(targetRow, anchor: .center)
                }
            }
            .contextMenu { copyContextMenu }
            .background(keyboardHandler)
            .background(theme.background)
        }
    }

    /// Detected file type from magic bytes, if any.
    private var detectedFileType: FileSignature? {
        MagicBytes.detect(from: displayData)
    }

    private var statusBar: some View {
        HStack {
            if let fileType = detectedFileType {
                Text(fileType.name)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(" · ")
                    .foregroundStyle(.secondary)
            }
            Text(fileSizeDescription)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if let sel = selectionDescription {
                Text("  |  ")
                    .foregroundStyle(.secondary)
                Text(sel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if isEditable && hexDocumentStorage.isModified {
                Text("  |  ")
                    .foregroundStyle(.secondary)
                Text("Modified")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            Spacer()
            if isEditable, let range = selectionRange, range.count == 1 {
                let idx = range.lowerBound
                Button {
                    hexDocumentStorage.insertByte(0x00, at: idx)
                } label: {
                    Image(systemName: "plus.square")
                }
                .help("Insert 0x00 byte at cursor")
                .buttonStyle(.borderless)

                Button {
                    performDeleteByte(at: idx)
                } label: {
                    Image(systemName: "minus.square")
                }
                .help("Delete byte at cursor")
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.background)
    }

    // MARK: - Section legend

    /// Compact legend showing detected section names and their colors.
    private var sectionLegendView: some View {
        HStack(spacing: 12) {
            // Deduplicate by SectionKind — show each kind only once
            let uniqueKinds: [(SectionKind, String)] = {
                var seen = Set<String>()
                var result: [(SectionKind, String)] = []
                for section in cachedSections {
                    let key = section.kind.label
                    if !seen.contains(key) && section.kind != .data {
                        seen.insert(key)
                        result.append((section.kind, section.name))
                    }
                }
                return result
            }()

            ForEach(uniqueKinds.indices, id: \.self) { i in
                let (kind, _) = uniqueKinds[i]
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(kind.color.opacity(0.4))
                        .frame(width: 10, height: 10)
                    Text(kind.label)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(theme.background)
    }

    // MARK: - Context menu

    @ViewBuilder
    private var copyContextMenu: some View {
        if let sel = selectedData {
            let startOffset = selectionRange?.lowerBound ?? 0
            Button("Copy as Hex String") {
                HexFormatter.copyToClipboard(sel, format: .hexString)
            }
            Button("Copy as C Array") {
                HexFormatter.copyToClipboard(sel, format: .cArray)
            }
            Button("Copy as Swift Array") {
                HexFormatter.copyToClipboard(sel, format: .swiftArray)
            }
            Button("Copy as Raw Bytes") {
                HexFormatter.copyToClipboard(sel, format: .rawBytes)
            }
            Button("Copy as Hex Dump") {
                HexFormatter.copyToClipboard(sel, format: .hexDump, startOffset: startOffset)
            }
            Divider()
        }
        Button("Select All") {
            selectionStart = 0
            selectionEnd = displayData.count - 1
        }
        .disabled(displayData.isEmpty)
        Button("Clear Selection") {
            selectionStart = nil
            selectionEnd = nil
            pendingNibble = nil
        }
        .disabled(selectionStart == nil)
    }

    // MARK: - Row rendering

    /// Build an `AttributedString` for the hex byte section of a row.
    /// Each byte is 3 characters ("xx "), with per-byte foreground and background colors.
    /// Returns a single `Text` view — dramatically fewer AttributeGraph nodes than
    /// 16 individual `Text` views with gestures.
    private func hexSectionAttributedString(_ row: HexRow, firstHalf: Bool) -> AttributedString {
        let rangeStart = firstHalf ? 0 : 8
        let rangeEnd = firstHalf ? 8 : 16
        var result = AttributedString()

        for i in rangeStart..<rangeEnd {
            var piece: AttributedString
            if i < row.bytes.count {
                let byte = row.bytes[row.bytes.startIndex + i]
                let absIdx = row.offset + i
                piece = AttributedString(String(format: "%02x ", byte))

                let isCursor = isEditable && isCursorByte(absIdx) && !asciiInputMode
                let isInSel = isSelected(absIdx) && !isCursor
                let matchHL = searchMatchHighlight(for: absIdx)
                let sectionBg = sectionBackground(for: absIdx)

                // Foreground
                piece.foregroundColor = isCursor ? theme.background : byteColor(byte)

                // Background: layer section bg, then highlight on top
                let highlight: Color = isCursor ? theme.selection
                    : (isInSel ? selectionHighlight
                    : (matchHL != Color.clear ? matchHL : .clear))
                if highlight != .clear {
                    piece.backgroundColor = highlight
                } else if sectionBg != .clear {
                    piece.backgroundColor = sectionBg
                }
            } else {
                piece = AttributedString("   ")
            }
            result.append(piece)
        }
        return result
    }

    /// Build an `AttributedString` for the ASCII sidebar of a row.
    /// Each byte is 1 character, with per-byte foreground and background colors.
    private func asciiSectionAttributedString(_ row: HexRow) -> AttributedString {
        var result = AttributedString()

        for i in 0..<row.bytes.count {
            let byte = row.bytes[row.bytes.startIndex + i]
            let absIdx = row.offset + i

            var piece = AttributedString(asciiCharacter(byte))

            let isCursor = isEditable && isCursorByte(absIdx) && asciiInputMode
            let isInSel = isSelected(absIdx) && !isCursor
            let matchHL = searchMatchHighlight(for: absIdx)
            let sectionBg = sectionBackground(for: absIdx)

            piece.foregroundColor = isCursor ? theme.background : byteColor(byte)

            let highlight: Color = isCursor ? theme.selection
                : (isInSel ? selectionHighlight
                : (matchHL != Color.clear ? matchHL : .clear))
            if highlight != .clear {
                piece.backgroundColor = highlight
            } else if sectionBg != .clear {
                piece.backgroundColor = sectionBg
            }

            result.append(piece)
        }
        return result
    }

    /// Compute the byte index within the row from a tap's x-coordinate in the hex section.
    /// Each hex byte occupies 3 monospace characters ("xx ").
    private func hexByteIndex(from locationX: CGFloat, charWidth: CGFloat, firstHalf: Bool) -> Int? {
        let charsPerByte: CGFloat = 3.0
        let byteWidth = charWidth * charsPerByte
        let localIndex = Int(locationX / byteWidth)
        let offset = firstHalf ? 0 : 8
        let index = offset + localIndex
        // Clamp to valid range
        if index < offset || index >= offset + 8 { return nil }
        return index
    }

    /// Compute the byte index within the row from a tap's x-coordinate in the ASCII section.
    /// Each ASCII byte occupies 1 monospace character.
    private func asciiByteIndex(from locationX: CGFloat, charWidth: CGFloat, byteCount: Int) -> Int? {
        let index = Int(locationX / charWidth)
        if index < 0 || index >= byteCount { return nil }
        return index
    }

    private func hexRowView(_ row: HexRow) -> some View {
        HStack(spacing: 0) {
            // Offset gutter
            Text(String(format: "%08x", row.offset))
                .foregroundStyle(theme.lineNumber)

            Text("  ")

            // Hex bytes — first 8 (single Text with AttributedString)
            Text(hexSectionAttributedString(row, firstHalf: true))
                .contentShape(Rectangle())
                .onTapGesture { location in
                    hexSectionTapped(row: row, location: location, firstHalf: true, extend: false)
                }
                #if os(macOS)
                .simultaneousGesture(
                    SpatialTapGesture().modifiers(.shift).onEnded { value in
                        hexSectionTapped(row: row, location: value.location, firstHalf: true, extend: true)
                    }
                )
                #endif

            // Wider gap between byte 8 and 9
            Text(" ")

            // Hex bytes — second 8 (single Text with AttributedString)
            Text(hexSectionAttributedString(row, firstHalf: false))
                .contentShape(Rectangle())
                .onTapGesture { location in
                    hexSectionTapped(row: row, location: location, firstHalf: false, extend: false)
                }
                #if os(macOS)
                .simultaneousGesture(
                    SpatialTapGesture().modifiers(.shift).onEnded { value in
                        hexSectionTapped(row: row, location: value.location, firstHalf: false, extend: true)
                    }
                )
                #endif

            Text(" ")

            // ASCII sidebar (single Text with AttributedString)
            Text("|")
                .foregroundStyle(theme.lineNumber)
            Text(asciiSectionAttributedString(row))
                .contentShape(Rectangle())
                .onTapGesture { location in
                    asciiSectionTapped(row: row, location: location, extend: false)
                }
                #if os(macOS)
                .simultaneousGesture(
                    SpatialTapGesture().modifiers(.shift).onEnded { value in
                        asciiSectionTapped(row: row, location: value.location, extend: true)
                    }
                )
                #endif
            Text("|")
                .foregroundStyle(theme.lineNumber)
        }
        .font(.system(.body, design: .monospaced))
    }

    /// Handle a tap on a hex section (first or second half of the row).
    /// Uses the tap x-coordinate to determine which byte was clicked.
    private func hexSectionTapped(row: HexRow, location: CGPoint, firstHalf: Bool, extend: Bool) {
        // Estimate monospace character width from system body font.
        // NSFont.monospacedSystemFont matches .system(.body, design: .monospaced).
        #if os(macOS)
        let charWidth: CGFloat = {
            let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let sample = NSAttributedString(string: "0", attributes: [.font: font])
            return sample.size().width
        }()
        #else
        let charWidth: CGFloat = 8.0 // reasonable fallback for iOS
        #endif

        guard let localIdx = hexByteIndex(from: location.x, charWidth: charWidth, firstHalf: firstHalf) else { return }
        let absIdx = row.offset + localIdx
        guard localIdx < row.bytes.count else { return }
        handleByteTap(absIdx, extend: extend, ascii: false)
    }

    /// Handle a tap on the ASCII section.
    private func asciiSectionTapped(row: HexRow, location: CGPoint, extend: Bool) {
        #if os(macOS)
        let charWidth: CGFloat = {
            let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let sample = NSAttributedString(string: "0", attributes: [.font: font])
            return sample.size().width
        }()
        #else
        let charWidth: CGFloat = 8.0
        #endif

        guard let localIdx = asciiByteIndex(from: location.x, charWidth: charWidth, byteCount: row.bytes.count) else { return }
        let absIdx = row.offset + localIdx
        handleByteTap(absIdx, extend: extend, ascii: true)
    }

    // MARK: - Selection logic

    /// Whether this byte index is the single-byte cursor (for editing).
    private func isCursorByte(_ index: Int) -> Bool {
        guard let range = selectionRange else { return false }
        return range.count == 1 && range.lowerBound == index
    }

    private func isSelected(_ index: Int) -> Bool {
        guard let range = selectionRange else { return false }
        return range.contains(index)
    }

    private func handleByteTap(_ index: Int, extend: Bool, ascii: Bool) {
        if extend, selectionStart != nil {
            selectionEnd = index
        } else {
            selectionStart = index
            selectionEnd = index
        }
        pendingNibble = nil
        if isEditable {
            asciiInputMode = ascii
        }
    }

    private var selectionHighlight: Color {
        theme.selection
    }

    /// Returns a highlight color if the byte at `index` falls within a search match.
    /// The current match gets a distinct orange highlight; other matches are yellow.
    private func searchMatchHighlight(for index: Int) -> Color {
        guard hexSearchState.isVisible, !hexSearchState.matches.isEmpty else {
            return Color.clear
        }
        for (i, match) in hexSearchState.matches.enumerated() {
            if match.contains(index) {
                return i == hexSearchState.currentMatchIndex
                    ? theme.string.opacity(0.6)
                    : theme.number.opacity(0.3)
            }
        }
        return Color.clear
    }

    // MARK: - Keyboard handling (edit mode)

    @ViewBuilder
    private var keyboardHandler: some View {
        if isEditable {
            #if os(macOS)
            HexKeyboardResponder(
                onHexDigit: { digit in handleHexDigit(digit) },
                onASCIIChar: { char in handleASCIIChar(char) },
                onDelete: { handleDelete() },
                onArrow: { direction in handleArrow(direction) },
                onEscape: {
                    selectionStart = nil
                    selectionEnd = nil
                    pendingNibble = nil
                },
                isASCIIMode: asciiInputMode
            )
            .frame(width: 0, height: 0)
            #else
            EmptyView()
            #endif
        } else {
            EmptyView()
        }
    }

    // MARK: - Edit input handling

    /// Process a hex digit (0-15) typed in the hex pane.
    private func handleHexDigit(_ digit: UInt8) {
        guard !asciiInputMode else { return }
        guard let range = selectionRange, range.count == 1 else { return }
        let idx = range.lowerBound
        guard idx < displayData.count else { return }

        if let high = pendingNibble {
            let newByte = (high << 4) | digit
            hexDocumentStorage.overwriteByte(at: idx, with: newByte)
            pendingNibble = nil
            advanceCursor()
        } else {
            pendingNibble = digit
        }
    }

    /// Process a printable ASCII character typed in the ASCII pane.
    private func handleASCIIChar(_ char: Character) {
        guard asciiInputMode else { return }
        guard let range = selectionRange, range.count == 1 else { return }
        let idx = range.lowerBound
        guard idx < displayData.count else { return }
        guard let ascii = char.asciiValue else { return }

        hexDocumentStorage.overwriteByte(at: idx, with: ascii)
        advanceCursor()
    }

    /// Delete the byte at the current cursor position.
    private func handleDelete() {
        guard let range = selectionRange, range.count == 1 else { return }
        performDeleteByte(at: range.lowerBound)
    }

    private func performDeleteByte(at idx: Int) {
        guard idx < displayData.count else { return }
        hexDocumentStorage.deleteByte(at: idx)
        let d = displayData
        if d.isEmpty {
            selectionStart = nil
            selectionEnd = nil
        } else if idx >= d.count {
            selectionStart = d.count - 1
            selectionEnd = d.count - 1
        }
        pendingNibble = nil
    }

    /// Move the cursor to the next byte.
    private func advanceCursor() {
        guard let s = selectionStart else { return }
        let next = s + 1
        if next < displayData.count {
            selectionStart = next
            selectionEnd = next
        }
    }

    /// Handle arrow key navigation.
    private func handleArrow(_ direction: ArrowDirection) {
        let d = displayData
        guard let range = selectionRange else {
            if !d.isEmpty {
                selectionStart = 0
                selectionEnd = 0
            }
            return
        }
        pendingNibble = nil

        // Use lowerBound for single cursor navigation
        let idx = range.lowerBound

        switch direction {
        case .left:
            if idx > 0 {
                selectionStart = idx - 1
                selectionEnd = idx - 1
            }
        case .right:
            if idx < d.count - 1 {
                selectionStart = idx + 1
                selectionEnd = idx + 1
            }
        case .up:
            if idx >= 16 {
                selectionStart = idx - 16
                selectionEnd = idx - 16
            }
        case .down:
            let next = idx + 16
            if next < d.count {
                selectionStart = next
                selectionEnd = next
            } else if d.count > 0 {
                selectionStart = d.count - 1
                selectionEnd = d.count - 1
            }
        }
    }

    // MARK: - Helpers

    /// Returns the printable ASCII character for a byte, or `.` for non-printable bytes.
    private func asciiCharacter(_ byte: UInt8) -> String {
        if byte >= 0x20 && byte <= 0x7E {
            return String(UnicodeScalar(byte))
        }
        return "."
    }

    /// Color-codes a byte value:
    /// - Null (0x00): dimmed
    /// - Printable ASCII (0x20-0x7E): default foreground
    /// - High bytes (>127): accent color
    /// - Other non-printable: secondary
    private func byteColor(_ byte: UInt8) -> Color {
        if byte == 0x00 {
            return theme.comment.opacity(0.5)
        } else if byte > 0x7F {
            return theme.keyword
        } else if byte >= 0x20 && byte <= 0x7E {
            return theme.plain
        } else {
            return theme.punctuation
        }
    }

    private var alternateRowBackground: Color {
        theme.lineNumber.opacity(0.08)
    }
}

// MARK: - Arrow direction

enum ArrowDirection {
    case left, right, up, down
}

// MARK: - macOS keyboard responder

#if os(macOS)
import AppKit

/// An NSView-backed responder that captures key events for the hex editor.
///
/// Placed as an invisible background view. When the hex content area is clicked,
/// the responder becomes first responder to receive key-down events.
struct HexKeyboardResponder: NSViewRepresentable {
    let onHexDigit: (UInt8) -> Void
    let onASCIIChar: (Character) -> Void
    let onDelete: () -> Void
    let onArrow: (ArrowDirection) -> Void
    let onEscape: () -> Void
    let isASCIIMode: Bool

    func makeNSView(context: Context) -> HexKeyView {
        let view = HexKeyView()
        view.onHexDigit = onHexDigit
        view.onASCIIChar = onASCIIChar
        view.onDelete = onDelete
        view.onArrow = onArrow
        view.onEscape = onEscape
        view.isASCIIMode = isASCIIMode
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: HexKeyView, context: Context) {
        nsView.onHexDigit = onHexDigit
        nsView.onASCIIChar = onASCIIChar
        nsView.onDelete = onDelete
        nsView.onArrow = onArrow
        nsView.onEscape = onEscape
        nsView.isASCIIMode = isASCIIMode
    }
}

/// NSView subclass that can become first responder and handle keyDown events.
class HexKeyView: NSView {
    var onHexDigit: ((UInt8) -> Void)?
    var onASCIIChar: ((Character) -> Void)?
    var onDelete: (() -> Void)?
    var onArrow: ((ArrowDirection) -> Void)?
    var onEscape: (() -> Void)?
    var isASCIIMode: Bool = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers, let char = chars.first else {
            super.keyDown(with: event)
            return
        }

        // Let Cmd-key combos pass through (undo/redo, copy, save, etc.)
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }

        // Arrow keys
        switch event.keyCode {
        case 123: onArrow?(.left); return
        case 124: onArrow?(.right); return
        case 125: onArrow?(.down); return
        case 126: onArrow?(.up); return
        default: break
        }

        // Escape
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        // Delete (backspace)
        if event.keyCode == 51 || char == Character(UnicodeScalar(0x7F)) {
            onDelete?()
            return
        }

        // Forward delete
        if event.keyCode == 117 {
            onDelete?()
            return
        }

        if isASCIIMode {
            if let av = char.asciiValue, av >= 0x20, av <= 0x7E {
                onASCIIChar?(char)
            }
        } else {
            if let nibble = hexValue(of: char) {
                onHexDigit?(nibble)
            }
        }
    }

    private func hexValue(of char: Character) -> UInt8? {
        switch char {
        case "0": return 0
        case "1": return 1
        case "2": return 2
        case "3": return 3
        case "4": return 4
        case "5": return 5
        case "6": return 6
        case "7": return 7
        case "8": return 8
        case "9": return 9
        case "a", "A": return 10
        case "b", "B": return 11
        case "c", "C": return 12
        case "d", "D": return 13
        case "e", "E": return 14
        case "f", "F": return 15
        default: return nil
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            return super.performKeyEquivalent(with: event)
        }
        return false
    }
}
#endif

// MARK: - Previews

#Preview("Hex View — read-only") {
    HexView(data: "Hello, World! This is a hex viewer test with enough text to span multiple rows.\n\0\u{80}\u{FF}".data(using: .utf8)!)
}

#Preview("Hex View — empty") {
    HexView(data: Data())
}

#Preview("Hex View — editable") {
    let doc = HexDocument(data: "Hello, World! Editable hex editor test.\n\0\u{80}\u{FF}".data(using: .utf8)!)
    HexView(hexDocument: doc)
}
