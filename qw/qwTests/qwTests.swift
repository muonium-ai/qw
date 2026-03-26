//
//  qwTests.swift
//  qwTests
//
//  Created by Senthil Nayagam on 10/01/26.
//

import XCTest
@testable import qw

final class qwTests: XCTestCase {

    func testSupportedFileTypePlainTextExists() {
        // Smoke test: verify the plain text file type is accessible
        XCTAssertEqual(SupportedFileType.plainText.rawValue, "txt")
    }
}
