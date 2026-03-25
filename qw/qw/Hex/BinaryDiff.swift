//
//  BinaryDiff.swift
//  qw
//
//  Binary diff engine for byte-by-byte comparison of two files.
//  Produces contiguous regions of equal/changed/added/removed bytes.
//  Ticket: T-000029
//

import Foundation

/// The type of a diff region between two binary files.
enum DiffRegionType: Equatable {
    /// Bytes are identical in both files.
    case equal
    /// Bytes exist at the same offset but differ in value.
    case changed
    /// Bytes exist in file B but have no counterpart in file A (B is longer).
    case addedInB
    /// Bytes exist in file A but have no counterpart in file B (A is longer).
    case removedFromA
}

/// A contiguous region of bytes sharing the same diff status.
struct DiffRegion: Identifiable {
    let id = UUID()
    /// Starting offset in file A for this region (or the offset where A ended).
    let offsetA: Int
    /// Starting offset in file B for this region (or the offset where B ended).
    let offsetB: Int
    /// Number of bytes in this region.
    let length: Int
    /// The diff status of the bytes in this region.
    let type: DiffRegionType
}

/// Engine for computing binary diffs between two Data blobs.
///
/// Uses a simple linear scan: bytes at the same offset are compared, and
/// consecutive bytes with the same status are grouped into regions. Trailing
/// bytes in the longer file are marked as added/removed.
struct BinaryDiffEngine {

    /// Compare two data blobs byte-by-byte and return contiguous diff regions.
    ///
    /// - Parameters:
    ///   - dataA: The first (left) file data.
    ///   - dataB: The second (right) file data.
    /// - Returns: An array of `DiffRegion` covering every byte in both files.
    static func diff(dataA: Data, dataB: Data) -> [DiffRegion] {
        var regions: [DiffRegion] = []
        let commonLength = min(dataA.count, dataB.count)

        if commonLength > 0 {
            var currentType: DiffRegionType = dataA[dataA.startIndex] == dataB[dataB.startIndex] ? .equal : .changed
            var regionStart = 0

            for i in 1..<commonLength {
                let byteA = dataA[dataA.startIndex + i]
                let byteB = dataB[dataB.startIndex + i]
                let status: DiffRegionType = byteA == byteB ? .equal : .changed

                if status != currentType {
                    regions.append(DiffRegion(
                        offsetA: regionStart,
                        offsetB: regionStart,
                        length: i - regionStart,
                        type: currentType
                    ))
                    currentType = status
                    regionStart = i
                }
            }

            // Flush the last common region
            regions.append(DiffRegion(
                offsetA: regionStart,
                offsetB: regionStart,
                length: commonLength - regionStart,
                type: currentType
            ))
        }

        // Trailing bytes only in A (A is longer)
        if dataA.count > commonLength {
            regions.append(DiffRegion(
                offsetA: commonLength,
                offsetB: commonLength,
                length: dataA.count - commonLength,
                type: .removedFromA
            ))
        }

        // Trailing bytes only in B (B is longer)
        if dataB.count > commonLength {
            regions.append(DiffRegion(
                offsetA: commonLength,
                offsetB: commonLength,
                length: dataB.count - commonLength,
                type: .addedInB
            ))
        }

        return regions
    }

    /// Count the total number of differing bytes (changed + added + removed).
    static func differingByteCount(in regions: [DiffRegion]) -> Int {
        regions.filter { $0.type != .equal }.reduce(0) { $0 + $1.length }
    }

    /// Return the indices of regions that contain differences (non-equal).
    static func diffRegionIndices(in regions: [DiffRegion]) -> [Int] {
        regions.enumerated().compactMap { $0.element.type != .equal ? $0.offset : nil }
    }
}
