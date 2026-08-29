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

    // MARK: - Event grouping

    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar.current.date(from: c)!
    }

    private let eightHours: TimeInterval = 8 * 3600

    func testLateNightShootStaysInOneEventDatedByItsStart() {
        // 11pm–1am, shots ~20 min apart: one event, all dated to the 3rd.
        let dates = [at(2026, 8, 3, 23, 0), at(2026, 8, 3, 23, 40),
                     at(2026, 8, 4, 0, 20), at(2026, 8, 4, 1, 0)]
        let starts = MediaOrganizer.eventStartDates(forSorted: dates, gap: eightHours)
        XCTAssertEqual(Set(starts), [at(2026, 8, 3, 23, 0)])
    }

    func testGapLargerThanThresholdStartsANewEvent() {
        let dates = [at(2026, 8, 3, 9, 0), at(2026, 8, 3, 9, 30),   // morning
                     at(2026, 8, 3, 21, 0), at(2026, 8, 3, 21, 15)] // evening, >8h later
        let starts = MediaOrganizer.eventStartDates(forSorted: dates, gap: eightHours)
        XCTAssertEqual(starts, [at(2026, 8, 3, 9, 0), at(2026, 8, 3, 9, 0),
                                at(2026, 8, 3, 21, 0), at(2026, 8, 3, 21, 0)])
    }

    func testGapDisabledKeepsEachTimestamp() {
        let dates = [at(2026, 8, 3, 23, 0), at(2026, 8, 4, 0, 30)]
        XCTAssertEqual(MediaOrganizer.eventStartDates(forSorted: dates, gap: 0), dates)
    }

    func testEmptyInput() {
        XCTAssertEqual(MediaOrganizer.eventStartDates(forSorted: [], gap: eightHours), [])
    }

    func testEventStartDrivesTheDestinationFolder() {
        let dates = [at(2026, 8, 3, 23, 0), at(2026, 8, 4, 1, 0)]
        let starts = MediaOrganizer.eventStartDates(forSorted: dates, gap: eightHours)
        let folders = starts.map {
            MediaOrganizer.relativeDestination(for: $0, sourceFolder: "100CANON", isVideo: false)
        }
        XCTAssertEqual(folders, ["2026/08-03/100CANON", "2026/08-03/100CANON"])
    }
}
