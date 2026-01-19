//
//  WordWrapTests.swift
//  qwTests
//
//  Tests for word wrap and horizontal scrolling behavior
//

import XCTest

#if os(macOS)
import AppKit
@testable import qw

final class WordWrapTests: XCTestCase {
    func testApplyWordWrapEnablesHorizontalScrollingWhenDisabled() {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            XCTFail("Expected NSTextView in scrollableTextView")
            return
        }

        MacOSTextEditor.applyWordWrap(false, to: textView, scrollView: scrollView)

        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertFalse(textView.textContainer?.widthTracksTextView ?? true)
        XCTAssertTrue(textView.isHorizontallyResizable)
    }

    func testApplyWordWrapDisablesHorizontalScrollingWhenEnabled() {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            XCTFail("Expected NSTextView in scrollableTextView")
            return
        }

        MacOSTextEditor.applyWordWrap(true, to: textView, scrollView: scrollView)

        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView ?? false)
        XCTAssertFalse(textView.isHorizontallyResizable)
    }
}
#endif
