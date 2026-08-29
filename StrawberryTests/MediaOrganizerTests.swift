//
//  MediaOrganizerTests.swift
//  StrawberryTests
//
//  Covers the pure path-derivation helper; the filesystem-walking parts aren't
//  exercised here.
//

import XCTest

final class MediaOrganizerTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    func testRelativeDestinationForPhoto() {
        let path = MediaOrganizer.relativeDestination(for: date(2026, 8, 3),
                                                      sourceFolder: "100CANON",
                                                      isVideo: false)
        XCTAssertEqual(path, "2026/08-03/100CANON")
    }

    func testRelativeDestinationForVideoGetsSuffix() {
        let path = MediaOrganizer.relativeDestination(for: date(2025, 12, 25),
                                                      sourceFolder: "100GOPRO",
                                                      isVideo: true)
        XCTAssertEqual(path, "2025/12-25/100GOPRO-video")
    }

    func testIsVideoFileIsCaseInsensitive() {
        XCTAssertTrue(MediaOrganizer.isVideoFile("MOV"))
        XCTAssertTrue(MediaOrganizer.isVideoFile("mp4"))
        XCTAssertFalse(MediaOrganizer.isVideoFile("jpg"))
        XCTAssertFalse(MediaOrganizer.isVideoFile("cr2"))
    }
}
