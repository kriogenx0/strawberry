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

final class ExistingFilePolicyTests: XCTestCase {

    func testRsyncFlagMapping() {
        XCTAssertNil(ExistingFilePolicy.overwrite.flag)
        XCTAssertEqual(ExistingFilePolicy.update.flag, "--update")
        XCTAssertEqual(ExistingFilePolicy.addOnly.flag, "--ignore-existing")
    }

    func testOverwriteRawValueIsLegacyOverride() {
        XCTAssertEqual(ExistingFilePolicy.overwrite.rawValue, "override")
    }

    func testDecodingUnknownRawValueFallsBackToOverwrite() throws {
        let data = Data("\"clobber\"".utf8)
        XCTAssertEqual(try JSONDecoder().decode(ExistingFilePolicy.self, from: data), .overwrite)
    }
}

final class RsyncOptionsTests: XCTestCase {

    func testDefaults() {
        let opts = RsyncOptions()
        XCTAssertFalse(opts.mirrorDelete)
        XCTAssertFalse(opts.removeSourceFiles)
        XCTAssertEqual(opts.existingFiles, .overwrite)
        XCTAssertTrue(opts.wholeFile)
        XCTAssertTrue(opts.preservePermissions)
        XCTAssertEqual(opts.bandwidthLimitMBps, 0)
        XCTAssertTrue(opts.excludes.contains(".DS_Store"))
    }

    func testDecodingPartialJSONKeepsDefaultsForMissingKeys() throws {
        let data = Data(#"{"mirrorDelete": true}"#.utf8)
        let opts = try JSONDecoder().decode(RsyncOptions.self, from: data)
        XCTAssertTrue(opts.mirrorDelete)
        XCTAssertTrue(opts.wholeFile)                       // default preserved
        XCTAssertEqual(opts.excludes, RsyncOptions.defaultExcludes)
    }

    func testEncodeDecodeRoundTrip() throws {
        var opts = RsyncOptions()
        opts.bandwidthLimitMBps = 12.5
        opts.existingFiles = .addOnly
        opts.extraArgs = ["--partial"]
        let data = try JSONEncoder().encode(opts)
        let back = try JSONDecoder().decode(RsyncOptions.self, from: data)
        XCTAssertEqual(back, opts)
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
        XCTAssertEqual(rule.options.existingFiles, .overwrite)
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
