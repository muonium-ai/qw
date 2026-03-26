//
//  BinaryDiffTests.swift
//  qwTests
//
//  Tests for BinaryDiffEngine: byte-by-byte binary diff.
//

#if os(macOS)
import XCTest
@testable import qw

final class BinaryDiffTests: XCTestCase {

    // MARK: - 1. Identical data

    func testIdenticalData_returnsSingleEqualRegion() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let regions = BinaryDiffEngine.diff(dataA: data, dataB: data)

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].type, .equal)
        XCTAssertEqual(regions[0].offsetA, 0)
        XCTAssertEqual(regions[0].offsetB, 0)
        XCTAssertEqual(regions[0].length, 4)
    }

    // MARK: - 2. Completely different data (same length)

    func testCompletelyDifferentSameLength_returnsSingleChangedRegion() {
        let a = Data([0x00, 0x00, 0x00])
        let b = Data([0xFF, 0xFF, 0xFF])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].type, .changed)
        XCTAssertEqual(regions[0].length, 3)
    }

    // MARK: - 3. Empty vs empty

    func testEmptyVsEmpty_returnsEmptyArray() {
        let regions = BinaryDiffEngine.diff(dataA: Data(), dataB: Data())
        XCTAssertTrue(regions.isEmpty)
    }

    // MARK: - 4. Empty vs non-empty

    func testEmptyVsNonEmpty_returnsAddedInB() {
        let b = Data([0x01, 0x02, 0x03])
        let regions = BinaryDiffEngine.diff(dataA: Data(), dataB: b)

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].type, .addedInB)
        XCTAssertEqual(regions[0].offsetA, 0)
        XCTAssertEqual(regions[0].offsetB, 0)
        XCTAssertEqual(regions[0].length, 3)
    }

    // MARK: - 5. Non-empty vs empty

    func testNonEmptyVsEmpty_returnsRemovedFromA() {
        let a = Data([0x01, 0x02, 0x03])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: Data())

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].type, .removedFromA)
        XCTAssertEqual(regions[0].offsetA, 0)
        XCTAssertEqual(regions[0].offsetB, 0)
        XCTAssertEqual(regions[0].length, 3)
    }

    // MARK: - 6. Mixed equal and changed

    func testMixedEqualAndChanged_returnsAlternatingRegions() {
        let a = Data([0x01, 0x02, 0x03])
        let b = Data([0x01, 0xFF, 0x03])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)

        XCTAssertEqual(regions.count, 3)

        XCTAssertEqual(regions[0].type, .equal)
        XCTAssertEqual(regions[0].offsetA, 0)
        XCTAssertEqual(regions[0].length, 1)

        XCTAssertEqual(regions[1].type, .changed)
        XCTAssertEqual(regions[1].offsetA, 1)
        XCTAssertEqual(regions[1].length, 1)

        XCTAssertEqual(regions[2].type, .equal)
        XCTAssertEqual(regions[2].offsetA, 2)
        XCTAssertEqual(regions[2].length, 1)
    }

    // MARK: - 7. A longer than B

    func testALongerThanB_hasRemovedFromATrailing() {
        let a = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let b = Data([0x01, 0x02, 0x03])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)

        // Common equal part + removedFromA trailing
        XCTAssertEqual(regions.count, 2)

        XCTAssertEqual(regions[0].type, .equal)
        XCTAssertEqual(regions[0].length, 3)

        XCTAssertEqual(regions[1].type, .removedFromA)
        XCTAssertEqual(regions[1].offsetA, 3)
        XCTAssertEqual(regions[1].offsetB, 3)
        XCTAssertEqual(regions[1].length, 2)
    }

    // MARK: - 8. B longer than A

    func testBLongerThanA_hasAddedInBTrailing() {
        let a = Data([0x01, 0x02])
        let b = Data([0x01, 0x02, 0x03, 0x04])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)

        XCTAssertEqual(regions.count, 2)

        XCTAssertEqual(regions[0].type, .equal)
        XCTAssertEqual(regions[0].length, 2)

        XCTAssertEqual(regions[1].type, .addedInB)
        XCTAssertEqual(regions[1].offsetA, 2)
        XCTAssertEqual(regions[1].offsetB, 2)
        XCTAssertEqual(regions[1].length, 2)
    }

    // MARK: - 9. Single byte equal

    func testSingleByteEqual() {
        let regions = BinaryDiffEngine.diff(dataA: Data([0xFF]), dataB: Data([0xFF]))

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].type, .equal)
        XCTAssertEqual(regions[0].length, 1)
    }

    // MARK: - 10. Single byte different

    func testSingleByteDifferent() {
        let regions = BinaryDiffEngine.diff(dataA: Data([0x00]), dataB: Data([0xFF]))

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].type, .changed)
        XCTAssertEqual(regions[0].length, 1)
    }

    // MARK: - 11. differingByteCount

    func testDifferingByteCount_sumsNonEqualRegions() {
        // [0x01, 0x02, 0x03, 0x04] vs [0x01, 0xFF, 0x03, 0xFF]
        // equal(1), changed(1), equal(1), changed(1) → differing = 2
        let a = Data([0x01, 0x02, 0x03, 0x04])
        let b = Data([0x01, 0xFF, 0x03, 0xFF])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)
        let count = BinaryDiffEngine.differingByteCount(in: regions)

        XCTAssertEqual(count, 2)
    }

    func testDifferingByteCount_includesAddedAndRemoved() {
        // A has 3 bytes, B has 5 bytes, first 3 identical → addedInB(2)
        let a = Data([0x01, 0x02, 0x03])
        let b = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)
        let count = BinaryDiffEngine.differingByteCount(in: regions)

        XCTAssertEqual(count, 2)
    }

    func testDifferingByteCount_zeroForIdentical() {
        let data = Data([0xAA, 0xBB, 0xCC])
        let regions = BinaryDiffEngine.diff(dataA: data, dataB: data)
        let count = BinaryDiffEngine.differingByteCount(in: regions)

        XCTAssertEqual(count, 0)
    }

    // MARK: - 12. diffRegionIndices

    func testDiffRegionIndices_returnsCorrectIndices() {
        // [0x01, 0x02, 0x03] vs [0x01, 0xFF, 0x03]
        // regions: [equal, changed, equal] → indices of non-equal: [1]
        let a = Data([0x01, 0x02, 0x03])
        let b = Data([0x01, 0xFF, 0x03])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)
        let indices = BinaryDiffEngine.diffRegionIndices(in: regions)

        XCTAssertEqual(indices, [1])
    }

    func testDiffRegionIndices_includesTrailingRegion() {
        // [0x01, 0x02] vs [0x01, 0x02, 0x03]
        // regions: [equal, addedInB] → indices: [1]
        let a = Data([0x01, 0x02])
        let b = Data([0x01, 0x02, 0x03])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)
        let indices = BinaryDiffEngine.diffRegionIndices(in: regions)

        XCTAssertEqual(indices, [1])
    }

    func testDiffRegionIndices_emptyForIdentical() {
        let data = Data([0x01, 0x02])
        let regions = BinaryDiffEngine.diff(dataA: data, dataB: data)
        let indices = BinaryDiffEngine.diffRegionIndices(in: regions)

        XCTAssertTrue(indices.isEmpty)
    }

    func testDiffRegionIndices_multipleNonEqualRegions() {
        // [0x01, 0x02, 0x03, 0x04] vs [0xFF, 0x02, 0xFF, 0x04]
        // regions: [changed, equal, changed, equal] → indices: [0, 2]
        let a = Data([0x01, 0x02, 0x03, 0x04])
        let b = Data([0xFF, 0x02, 0xFF, 0x04])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)
        let indices = BinaryDiffEngine.diffRegionIndices(in: regions)

        XCTAssertEqual(indices, [0, 2])
    }

    // MARK: - 13. Region offsets and lengths

    func testRegionOffsetsAndLengths_multipleRegions() {
        // [0xAA, 0xAA, 0xBB, 0xBB, 0xCC] vs [0xAA, 0xAA, 0xFF, 0xFF, 0xCC]
        // equal(0,2), changed(2,2), equal(4,1)
        let a = Data([0xAA, 0xAA, 0xBB, 0xBB, 0xCC])
        let b = Data([0xAA, 0xAA, 0xFF, 0xFF, 0xCC])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)

        XCTAssertEqual(regions.count, 3)

        XCTAssertEqual(regions[0].offsetA, 0)
        XCTAssertEqual(regions[0].offsetB, 0)
        XCTAssertEqual(regions[0].length, 2)
        XCTAssertEqual(regions[0].type, .equal)

        XCTAssertEqual(regions[1].offsetA, 2)
        XCTAssertEqual(regions[1].offsetB, 2)
        XCTAssertEqual(regions[1].length, 2)
        XCTAssertEqual(regions[1].type, .changed)

        XCTAssertEqual(regions[2].offsetA, 4)
        XCTAssertEqual(regions[2].offsetB, 4)
        XCTAssertEqual(regions[2].length, 1)
        XCTAssertEqual(regions[2].type, .equal)
    }

    func testRegionOffsets_withTrailingAdded() {
        // [0x01] vs [0x01, 0x02, 0x03]
        // equal(offset 0, len 1), addedInB(offset 1, len 2)
        let a = Data([0x01])
        let b = Data([0x01, 0x02, 0x03])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)

        XCTAssertEqual(regions.count, 2)

        XCTAssertEqual(regions[0].offsetA, 0)
        XCTAssertEqual(regions[0].offsetB, 0)
        XCTAssertEqual(regions[0].length, 1)

        XCTAssertEqual(regions[1].offsetA, 1)
        XCTAssertEqual(regions[1].offsetB, 1)
        XCTAssertEqual(regions[1].length, 2)
        XCTAssertEqual(regions[1].type, .addedInB)
    }

    // MARK: - 14. Total coverage

    func testTotalCoverage_sameLengthIdentical() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let regions = BinaryDiffEngine.diff(dataA: data, dataB: data)
        let totalLength = regions.reduce(0) { $0 + $1.length }

        XCTAssertEqual(totalLength, data.count)
    }

    func testTotalCoverage_sameLengthMixed() {
        let a = Data([0x01, 0x02, 0x03, 0x04])
        let b = Data([0x01, 0xFF, 0x03, 0xFF])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)
        let totalLength = regions.reduce(0) { $0 + $1.length }

        XCTAssertEqual(totalLength, max(a.count, b.count))
    }

    func testTotalCoverage_differentLengthsALonger() {
        let a = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let b = Data([0x01, 0xFF])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)
        let totalLength = regions.reduce(0) { $0 + $1.length }

        XCTAssertEqual(totalLength, max(a.count, b.count))
    }

    func testTotalCoverage_differentLengthsBLonger() {
        let a = Data([0xAA])
        let b = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let regions = BinaryDiffEngine.diff(dataA: a, dataB: b)
        let totalLength = regions.reduce(0) { $0 + $1.length }

        XCTAssertEqual(totalLength, max(a.count, b.count))
    }

    func testTotalCoverage_emptyInputs() {
        let regions = BinaryDiffEngine.diff(dataA: Data(), dataB: Data())
        let totalLength = regions.reduce(0) { $0 + $1.length }

        XCTAssertEqual(totalLength, 0)
    }
}
#endif
