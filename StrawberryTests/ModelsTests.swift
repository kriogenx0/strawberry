//
//  ModelsTests.swift
//  StrawberryTests
//
//  Basic coverage for the pure value types in Sync/Models.swift.
//

import XCTest

final class SyncIntervalTests: XCTestCase {

    func testSecondsForFixedIntervals() {
        XCTAssertNil(SyncInterval.manual.seconds)
        XCTAssertEqual(SyncInterval.hourly.seconds, 3600)
        XCTAssertEqual(SyncInterval.sixHours.seconds, 6 * 3600)
        XCTAssertEqual(SyncInterval.twelveHours.seconds, 12 * 3600)
        XCTAssertEqual(SyncInterval.daily.seconds, 24 * 3600)
        XCTAssertEqual(SyncInterval.weekly.seconds, 7 * 24 * 3600)
        XCTAssertNil(SyncInterval.monthly.seconds)
    }

    func testNextDueForDurationBasedInterval() {
        let last = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(SyncInterval.daily.nextDue(after: last),
                       last.addingTimeInterval(24 * 3600))
    }

    func testNextDueForManualIsNil() {
        XCTAssertNil(SyncInterval.manual.nextDue(after: Date()))
    }

    func testNextDueForMonthlyTracksCalendarMonth() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 31
        let jan31 = Calendar.current.date(from: comps)!
        let due = SyncInterval.monthly.nextDue(after: jan31)
        XCTAssertNotNil(due)
        // One calendar month after Jan 31 lands in (late) February, not March.
        XCTAssertEqual(Calendar.current.component(.month, from: due!), 2)
    }

    func testIsDue() {
        let last = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(SyncInterval.hourly.isDue(since: last,
                                                at: last.addingTimeInterval(3601)))
        XCTAssertFalse(SyncInterval.hourly.isDue(since: last,
                                                 at: last.addingTimeInterval(3599)))
        XCTAssertFalse(SyncInterval.manual.isDue(since: last,
                                                 at: last.addingTimeInterval(1_000_000)))
    }

    func testDecodingUnknownRawValueFallsBackToDaily() throws {
        let data = Data("\"every-fortnight\"".utf8)
        XCTAssertEqual(try JSONDecoder().decode(SyncInterval.self, from: data), .daily)
    }

    func testDecodingKnownRawValueRoundTrips() throws {
        let data = Data("\"weekly\"".utf8)
        XCTAssertEqual(try JSONDecoder().decode(SyncInterval.self, from: data), .weekly)
    }
}

final class SyncModeTests: XCTestCase {

    func testRsyncFlagMapping() {
        XCTAssertNil(SyncMode.append.rsyncFlag)
        XCTAssertEqual(SyncMode.mirror.rsyncFlag, "--delete-during")
        XCTAssertEqual(SyncMode.move.rsyncFlag, "--remove-source-files")
    }

    func testDecodingUnknownRawValueFallsBackToAppend() throws {
        let data = Data("\"sideways\"".utf8)
        XCTAssertEqual(try JSONDecoder().decode(SyncMode.self, from: data), .append)
    }

    func testDecodingKnownRawValueRoundTrips() throws {
        XCTAssertEqual(try JSONDecoder().decode(SyncMode.self, from: Data("\"mirror\"".utf8)), .mirror)
    }

    func testOnlyMoveTouchesTheSource() {
        XCTAssertTrue(SyncMode.move.sourceEffect.lowercased().contains("deleted"))
        XCTAssertEqual(SyncMode.append.sourceEffect, "Left as-is.")
        XCTAssertEqual(SyncMode.mirror.sourceEffect, "Left as-is.")
    }

    func testOnlyMirrorDeletesAtTheDestination() {
        XCTAssertTrue(SyncMode.mirror.destinationEffect.lowercased().contains("deleted"))
        XCTAssertTrue(SyncMode.append.destinationEffect.lowercased().contains("kept"))
        XCTAssertTrue(SyncMode.move.destinationEffect.lowercased().contains("nothing is deleted"))
    }
}

final class RsyncOptionsTests: XCTestCase {

    func testDefaults() {
        let opts = RsyncOptions()
        XCTAssertEqual(opts.mode, .append)
        XCTAssertTrue(opts.wholeFile)
        XCTAssertTrue(opts.preservePermissions)
        XCTAssertEqual(opts.bandwidthLimitMBps, 0)
        XCTAssertTrue(opts.excludes.contains(".DS_Store"))
    }

    func testDecodingPartialJSONKeepsDefaultsForMissingKeys() throws {
        let data = Data(#"{"mode":"mirror"}"#.utf8)
        let opts = try JSONDecoder().decode(RsyncOptions.self, from: data)
        XCTAssertEqual(opts.mode, .mirror)
        XCTAssertTrue(opts.wholeFile)                       // default preserved
        XCTAssertEqual(opts.excludes, RsyncOptions.defaultExcludes)
    }

    func testMigratesLegacyRemoveSourceFilesToMove() throws {
        let data = Data(#"{"removeSourceFiles": true, "mirrorDelete": true}"#.utf8)
        let opts = try JSONDecoder().decode(RsyncOptions.self, from: data)
        XCTAssertEqual(opts.mode, .move)   // move wins over mirror
    }

    func testMigratesLegacyMirrorDeleteToMirror() throws {
        let data = Data(#"{"mirrorDelete": true}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RsyncOptions.self, from: data).mode, .mirror)
    }

    func testMigratesLegacyPlainRuleToAppend() throws {
        let data = Data(#"{"wholeFile": false}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RsyncOptions.self, from: data).mode, .append)
    }

    func testEncodeDecodeRoundTrip() throws {
        var opts = RsyncOptions()
        opts.bandwidthLimitMBps = 12.5
        opts.mode = .move
        opts.extraArgs = ["--partial"]
        let data = try JSONEncoder().encode(opts)
        let back = try JSONDecoder().decode(RsyncOptions.self, from: data)
        XCTAssertEqual(back, opts)
    }

    func testEncodedJSONHasNoLegacyKeys() throws {
        let data = try JSONEncoder().encode(RsyncOptions())
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("mirrorDelete"))
        XCTAssertFalse(json.contains("removeSourceFiles"))
        XCTAssertFalse(json.contains("existingFiles"))
        XCTAssertTrue(json.contains("\"mode\""))
    }
}

final class SyncRuleTests: XCTestCase {

    func testMemberwiseInitDefaults() {
        let rule = SyncRule(name: "Photos", source: "/a", destination: "/b")
        XCTAssertEqual(rule.interval, .daily)
        XCTAssertTrue(rule.enabled)
        XCTAssertNil(rule.lastSuccessAt)
    }

    func testDecodingMinimalJSONAppliesDefaults() throws {
        let data = Data(#"{"name":"X","source":"/s","destination":"/d"}"#.utf8)
        let rule = try JSONDecoder().decode(SyncRule.self, from: data)
        XCTAssertEqual(rule.name, "X")
        XCTAssertEqual(rule.interval, .daily)
        XCTAssertTrue(rule.enabled)
        XCTAssertEqual(rule.options.mode, .append)
    }

    func testDecodingEmptyObjectGetsPlaceholderFields() throws {
        let rule = try JSONDecoder().decode(SyncRule.self, from: Data("{}".utf8))
        XCTAssertEqual(rule.name, "Rule")
        XCTAssertEqual(rule.source, "")
    }
}

final class AppConfigTests: XCTestCase {

    func testDefaults() {
        let cfg = AppConfig()
        XCTAssertTrue(cfg.rules.isEmpty)
        XCTAssertEqual(cfg.rsyncPath, "/opt/homebrew/bin/rsync")
        XCTAssertEqual(cfg.historyLimit, 500)
        XCTAssertTrue(cfg.showFailureDialog)
    }

    func testDecodingEmptyObjectUsesDefaults() throws {
        let cfg = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(cfg.rsyncPath, "/opt/homebrew/bin/rsync")
        XCTAssertEqual(cfg.historyLimit, 500)
    }
}
