//
//  AppVersionTests.swift
//  Local Response MapperTests
//

import XCTest

final class AppVersionTests: XCTestCase {

    /// The case that broke the old digit-joining compare: 3.0.0 became 300 and
    /// 2.0.30 became 2030, so the update never offered itself.
    func testMajorBumpAfterWidePatchIsNewer() {
        XCTAssertTrue(AppVersion.isNewer("3.0.0", than: "2.0.30"))
        XCTAssertFalse(AppVersion.isNewer("2.0.30", than: "3.0.0"))
    }

    func testMinorBumpBeatsWiderPatch() {
        XCTAssertTrue(AppVersion.isNewer("2.1.0", than: "2.0.10"))
        XCTAssertFalse(AppVersion.isNewer("2.0.10", than: "2.1.0"))
    }

    func testPatchOrdering() {
        XCTAssertTrue(AppVersion.isNewer("2.0.31", than: "2.0.30"))
        XCTAssertTrue(AppVersion.isNewer("2.0.10", than: "2.0.9"))
        XCTAssertFalse(AppVersion.isNewer("2.0.9", than: "2.0.10"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(AppVersion.isNewer("2.0.30", than: "2.0.30"))
    }

    /// GitHub tags are often written `v3.0.0`, and a shorter tag pads with zeros.
    func testTagPrefixAndMissingComponents() {
        XCTAssertTrue(AppVersion.isNewer("v3.0.0", than: "2.0.30"))
        XCTAssertTrue(AppVersion.isNewer("v3", than: "2.9.9"))
        XCTAssertFalse(AppVersion.isNewer("v3.0", than: "3.0.0"))
        XCTAssertTrue(AppVersion.isNewer("3.0.1", than: "3.0"))
    }

    /// Anything unparseable must not prompt an update.
    func testNonNumericVersionsAreNotNewer() {
        XCTAssertFalse(AppVersion.isNewer("nightly", than: "2.0.30"))
        XCTAssertFalse(AppVersion.isNewer("3.0.0-beta1", than: "2.0.30"))
        XCTAssertFalse(AppVersion.isNewer("", than: "2.0.30"))
        XCTAssertFalse(AppVersion.isNewer("3.0.0", than: ""))
    }
}
