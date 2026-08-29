//
//  AutoMediaSyncConfigTests.swift
//  StrawberryTests
//

import XCTest

final class AutoMediaSyncConfigTests: XCTestCase {

    func testDefaultsToEnabled() {
        let cfg = AutoMediaSyncConfig(destinationURL: URL(fileURLWithPath: "/Volumes/Photos"))
        XCTAssertTrue(cfg.isEnabled)
    }

    func testDisplayNameIsLastPathComponent() {
        let cfg = AutoMediaSyncConfig(destinationURL: URL(fileURLWithPath: "/Users/me/Pictures/Imports"))
        XCTAssertEqual(cfg.displayName, "Imports")
    }

    func testCodableRoundTrip() throws {
        let original = AutoMediaSyncConfig(destinationURL: URL(fileURLWithPath: "/Volumes/Big/Camera"),
                                          isEnabled: false)
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(AutoMediaSyncConfig.self, from: data)
        XCTAssertEqual(back.destinationURL, original.destinationURL)
        XCTAssertEqual(back.isEnabled, original.isEnabled)
    }
}
