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

    // MARK: - Annotation state

    @State private var showAnnotationPanel: Bool = false
    @State private var cachedAnnotations: [FieldValue] = []
    @State private var cachedAnnotationsDataCount: Int = -1

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
        self._hexDocumentStorage = ObservedObject(wrappedValue: HexDocument(data: Data()))
        self.isEditable = false
    }

    /// Standard read-only initializer for in-memory data.
    init(data: Data) {
        self.readOnlyData = data
        self._hexDocumentStorage = ObservedObject(wrappedValue: HexDocument(data: Data()))
        self.isEditable = false
    }

    /// Editable initializer — full editing support with undo/redo.
    init(hexDocument: HexDocument) {
        self.readOnlyData = nil
        self._hexDocumentStorage = ObservedObject(wrappedValue: hexDocument)
        self.isEditable = true
    }

    // MARK: - Computed

    /// The data to display.
    private var displayData: Data {
        isEditable ? hexDocumentStorage.currentData : (readOnlyData ?? Data())
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

    /// Tooltip for a byte from field annotations, if any.
    private func annotationTooltip(for index: Int) -> String? {
        FileAnnotator.tooltip(for: index, in: cachedAnnotations)
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
                    AnnotationPanelView(annotations: cachedAnnotations)
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
            }
        }
        .onAppear {
            if isEditable {
                hexDocumentStorage.undoManager = environmentUndoManager
            }
            updateSectionsIfNeeded()
            updateAnnotationsIfNeeded()
        }
        .onChange(of: environmentUndoManager) { _, newValue in
            if isEditable {
                hexDocumentStorage.undoManager = newValue
            }
        }
        .onChange(of: displayData.count) { _, _ in
            updateSectionsIfNeeded()
            updateAnnotationsIfNeeded()
        }
    }

    // MARK: - Subviews

    private var emptyView: some View {
        VStack {
            Spacer()
            Text("Empty file")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
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
    }

    private var hexContent: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { index in
                    let r = row(at: index)
                    hexRowView(r)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index.isMultiple(of: 2) ? Color.clear : alternateRowBackground)
                }
            }
        }
        .contextMenu { copyContextMenu }
        .background(keyboardHandler)
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
        .background {
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color(uiColor: .secondarySystemBackground)
            #endif
        }
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
        .background {
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color(uiColor: .secondarySystemBackground)
            #endif
        }
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

    private func hexRowView(_ row: HexRow) -> some View {
        HStack(spacing: 0) {
            // Offset gutter
            Text(String(format: "%08x", row.offset))
                .foregroundStyle(.secondary)

            Text("  ")

            // Hex bytes — first 8
            ForEach(0..<8, id: \.self) { i in
                if i < row.bytes.count {
                    let byte = row.bytes[row.bytes.startIndex + i]
                    hexByteView(byte: byte, absoluteIndex: row.offset + i)
                } else {
                    Text("   ")
                }
            }

            // Wider gap between byte 8 and 9
            Text(" ")

            // Hex bytes — second 8
            ForEach(8..<16, id: \.self) { i in
                if i < row.bytes.count {
                    let byte = row.bytes[row.bytes.startIndex + i]
                    hexByteView(byte: byte, absoluteIndex: row.offset + i)
                } else {
                    Text("   ")
                }
            }

            Text(" ")

            // ASCII sidebar
            Text("|")
                .foregroundStyle(.secondary)
            ForEach(0..<row.bytes.count, id: \.self) { i in
                let byte = row.bytes[row.bytes.startIndex + i]
                asciiByteView(byte: byte, absoluteIndex: row.offset + i)
            }
            Text("|")
                .foregroundStyle(.secondary)
        }
        .font(.system(.body, design: .monospaced))
    }

    /// A single hex byte cell that supports click-to-select and shift-click-to-extend.
    /// In edit mode, the cursor byte has an opaque accent highlight.
    /// Search matches are highlighted; the current match uses a distinct color.
    private func hexByteView(byte: UInt8, absoluteIndex: Int) -> some View {
        let isCursor = isEditable && isCursorByte(absoluteIndex) && !asciiInputMode
        let isInSelection = isSelected(absoluteIndex) && !isCursor
        let matchHighlight = searchMatchHighlight(for: absoluteIndex)
        let sectionBg = sectionBackground(for: absoluteIndex)
        let fgHighlight: Color = isCursor ? Color.accentColor.opacity(0.8)
            : (isInSelection ? selectionHighlight
            : (matchHighlight != Color.clear ? matchHighlight : .clear))

        let tooltip = annotationTooltip(for: absoluteIndex) ?? sectionTooltip(for: absoluteIndex)

        return Text(String(format: "%02x ", byte))
            .foregroundStyle(isCursor ? Color.white : byteColor(byte))
            .background(
                ZStack {
                    sectionBg
                    fgHighlight
                }
            )
            .contentShape(Rectangle())
            .help(tooltip ?? "")
            .onTapGesture {
                handleByteTap(absoluteIndex, extend: false, ascii: false)
            }
            #if os(macOS)
            .simultaneousGesture(
                TapGesture().modifiers(.shift).onEnded {
                    handleByteTap(absoluteIndex, extend: true, ascii: false)
                }
            )
            #endif
    }

    /// A single ASCII byte cell that mirrors selection highlighting.
    /// In edit mode with ASCII input, the cursor byte has an opaque accent highlight.
    /// Search matches are highlighted; the current match uses a distinct color.
    private func asciiByteView(byte: UInt8, absoluteIndex: Int) -> some View {
        let isCursor = isEditable && isCursorByte(absoluteIndex) && asciiInputMode
        let isInSelection = isSelected(absoluteIndex) && !isCursor
        let matchHighlight = searchMatchHighlight(for: absoluteIndex)
        let sectionBg = sectionBackground(for: absoluteIndex)
        let fgHighlight: Color = isCursor ? Color.accentColor.opacity(0.8)
            : (isInSelection ? selectionHighlight
            : (matchHighlight != Color.clear ? matchHighlight : .clear))

        let tooltip = annotationTooltip(for: absoluteIndex) ?? sectionTooltip(for: absoluteIndex)

        return Text(asciiCharacter(byte))
            .foregroundStyle(isCursor ? Color.white : byteColor(byte))
            .background(
                ZStack {
                    sectionBg
                    fgHighlight
                }
            )
            .contentShape(Rectangle())
            .help(tooltip ?? "")
            .onTapGesture {
                handleByteTap(absoluteIndex, extend: false, ascii: true)
            }
            #if os(macOS)
            .simultaneousGesture(
                TapGesture().modifiers(.shift).onEnded {
                    handleByteTap(absoluteIndex, extend: true, ascii: true)
                }
            )
            #endif
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
        Color.accentColor.opacity(0.3)
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
                    ? Color.orange.opacity(0.6)
                    : Color.yellow.opacity(0.35)
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
            return .secondary.opacity(0.5)
        } else if byte > 0x7F {
            return .accentColor
        } else if byte >= 0x20 && byte <= 0x7E {
            #if os(macOS)
            return Color(nsColor: .labelColor)
            #else
            return Color(uiColor: .label)
            #endif
        } else {
            return .secondary
        }
    }

    private var alternateRowBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor).opacity(0.5)
        #else
        Color(uiColor: .secondarySystemBackground).opacity(0.5)
        #endif
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
