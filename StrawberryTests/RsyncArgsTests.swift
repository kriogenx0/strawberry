//
//  RsyncArgsTests.swift
//  StrawberryTests
//
//  Pins the rsync flags each SyncMode produces — in particular that nothing
//  except Move can ever delete from the source.
//

import XCTest

final class RsyncArgsTests: XCTestCase {

    private let caps = RsyncCaps(version: "3.2", major: 3, minor: 2,
                                 prealloc: true, infoFlag: true, mkpath: true)

    private func rule(mode: SyncMode, extraArgs: [String] = []) -> SyncRule {
        var r = SyncRule(name: "r", source: "/src", destination: "/dst")
        r.options.mode = mode
        r.options.extraArgs = extraArgs
        return r
    }

    private func args(_ mode: SyncMode, extra: [String] = []) -> [String] {
        RsyncRunner.argumentList(for: rule(mode: mode, extraArgs: extra), dryRun: false, caps: caps)
    }

    func testAppendNeverDeletesOrMoves() {
        let a = args(.append)
        XCTAssertFalse(a.contains("--delete-during"))
        XCTAssertFalse(a.contains("--remove-source-files"))
    }

    func testMirrorDeletesAtDestinationButNotFromSource() {
        let a = args(.mirror)
        XCTAssertTrue(a.contains("--delete-during"))
        XCTAssertFalse(a.contains("--remove-source-files"))
        XCTAssertFalse(a.contains("--remove-source-dirs"))
    }

    func testMoveRemovesFromSource() {
        let a = args(.move)
        XCTAssertTrue(a.contains("--remove-source-files"))
        XCTAssertFalse(a.contains("--delete-during"))
    }

    func testExtraArgsCannotSmuggleSourceDeletionIntoMirror() {
        let a = args(.mirror, extra: ["--remove-source-files", "--remove-source-dirs", "--timeout=600"])
        XCTAssertFalse(a.contains("--remove-source-files"))
        XCTAssertFalse(a.contains("--remove-source-dirs"))
        XCTAssertTrue(a.contains("--timeout=600"))   // unrelated extras still pass through
    }

    func testMoveModeStillHonorsAnExplicitRemoveSourceDirs() {
        XCTAssertTrue(args(.move, extra: ["--remove-source-dirs"]).contains("--remove-source-dirs"))
    }
}
