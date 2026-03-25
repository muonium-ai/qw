//
//  HexDocument.swift
//  qw
//
//  Editable hex document model with undo/redo support.
//  Ticket: T-000020
//

import Combine
import Foundation
import SwiftUI

/// Manages binary data editing with undo/redo support.
///
/// Uses a simple mutable `Data` buffer for the current state. Each edit
/// method records an undo action so that `UndoManager` (Cmd+Z / Cmd+Shift+Z)
/// works transparently. A future ticket (T-000023) may replace the internal
/// storage with a patch-list for large-file support.
final class HexDocument: ObservableObject {

    // MARK: - Published state

    /// The current (potentially modified) bytes.
    @Published private(set) var currentData: Data

    /// Whether any edits have been made since the last save (or initial load).
    @Published private(set) var isModified: Bool = false

    // MARK: - Private state

    /// Snapshot of the data as originally loaded (or last saved).
    private var originalData: Data

    /// The file URL this document was loaded from, if any.
    private(set) var fileURL: URL?

    /// Undo manager wired up by the view layer.
    var undoManager: UndoManager?

    // MARK: - Init

    /// Create a hex document from raw data, optionally associated with a file URL.
    init(data: Data, fileURL: URL? = nil) {
        self.originalData = data
        self.currentData = data
        self.fileURL = fileURL
    }

    // MARK: - Editing operations

    /// Overwrite a single byte at `offset` with `newByte`.
    ///
    /// Registers an undo action that restores the previous byte value.
    func overwriteByte(at offset: Int, with newByte: UInt8) {
        guard offset >= 0, offset < currentData.count else { return }

        let oldByte = currentData[offset]
        guard oldByte != newByte else { return }

        currentData[offset] = newByte
        markModified()

        undoManager?.registerUndo(withTarget: self) { [weak self] target in
            target.overwriteByte(at: offset, with: oldByte)
        }
        undoManager?.setActionName("Overwrite Byte")
    }

    /// Insert a single byte at `offset`, shifting subsequent bytes right.
    ///
    /// Valid offsets are `0 ... currentData.count` (inserting at count appends).
    func insertByte(_ byte: UInt8, at offset: Int) {
        guard offset >= 0, offset <= currentData.count else { return }

        currentData.insert(byte, at: offset)
        markModified()

        undoManager?.registerUndo(withTarget: self) { [weak self] target in
            target.deleteByte(at: offset)
        }
        undoManager?.setActionName("Insert Byte")
    }

    /// Delete the byte at `offset`, shifting subsequent bytes left.
    func deleteByte(at offset: Int) {
        guard offset >= 0, offset < currentData.count else { return }

        let oldByte = currentData[offset]
        currentData.remove(at: offset)
        markModified()

        undoManager?.registerUndo(withTarget: self) { [weak self] target in
            target.insertByte(oldByte, at: offset)
        }
        undoManager?.setActionName("Delete Byte")
    }

    // MARK: - Persistence

    /// Write the current data to the given URL (or the original `fileURL`).
    func save(to url: URL? = nil) throws {
        guard let destination = url ?? fileURL else {
            throw CocoaError(.fileWriteNoPermission,
                             userInfo: [NSLocalizedDescriptionKey: "No file URL to save to."])
        }
        try currentData.write(to: destination)
        originalData = currentData
        isModified = false
        fileURL = destination
    }

    // MARK: - Helpers

    private func markModified() {
        isModified = (currentData != originalData)
    }
}
