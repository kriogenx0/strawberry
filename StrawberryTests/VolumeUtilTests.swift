//
//  VolumeUtilTests.swift
//  StrawberryTests
//
//  Endpoint-availability checks — the safety net that keeps a sync (especially a
//  Mirror) from running against a /Volumes drive that isn't mounted.
//

import XCTest

final class VolumeUtilTests: XCTestCase {

    /// A /Volumes name that is essentially guaranteed not to be a real mount.
    private let ghost = "StrawberryGhostVolume-\(UUID().uuidString)"

    // MARK: mountedVolumeCheck

    func testNonVolumePathIsNotChecked() {
        XCTAssertNil(VolumeUtil.mountedVolumeCheck(for: "/Users/someone/Pictures"))
        XCTAssertNil(VolumeUtil.mountedVolumeCheck(for: NSHomeDirectory() + "/x"))
    }

    func testUnmountedVolumeIsReportedNotMounted() {
        let result = VolumeUtil.mountedVolumeCheck(for: "/Volumes/\(ghost)/Backup/Set")
        XCTAssertEqual(result?.name, ghost)
        XCTAssertEqual(result?.mounted, false)
    }

    func testARealMountedVolumeIsReportedMounted() throws {
        // Find something actually mounted under /Volumes to assert the positive case.
        let mounted = FileManager.default
            .mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        guard let vol = mounted.first(where: { $0.path.hasPrefix("/Volumes/") }) else {
            throw XCTSkip("no volume mounted under /Volumes to test the positive path")
        }
        let name = vol.lastPathComponent
        let result = VolumeUtil.mountedVolumeCheck(for: "/Volumes/\(name)/anything")
        XCTAssertEqual(result?.name, name)
        XCTAssertEqual(result?.mounted, true)
    }

    // MARK: destinationAvailable / sourceAvailable

    func testDestinationOnUnmountedVolumeIsUnavailable() {
        let a = VolumeUtil.destinationAvailable("/Volumes/\(ghost)/Redundancy/Saturn")
        XCTAssertFalse(a.ok)
        XCTAssertEqual(a.reason, "drive “\(ghost)” is not mounted")
    }

    func testSourceOnUnmountedVolumeIsUnavailable() {
        let a = VolumeUtil.sourceAvailable("/Volumes/\(ghost)")
        XCTAssertFalse(a.ok)
        XCTAssertEqual(a.reason, "drive “\(ghost)” is not mounted")
    }

    func testEmptySourceIsUnavailable() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sb-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = VolumeUtil.sourceAvailable(dir.path)
        XCTAssertFalse(a.ok)
        XCTAssertEqual(a.reason, "source folder is empty")
    }

    func testNonEmptyLocalSourceIsAvailable() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sb-full-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertTrue(VolumeUtil.sourceAvailable(dir.path).ok)
    }

    func testEmptyPathStrings() {
        XCTAssertFalse(VolumeUtil.sourceAvailable("").ok)
        XCTAssertFalse(VolumeUtil.destinationAvailable("").ok)
    }

    func testAvailabilityCombinesBothEndpoints() {
        let a = VolumeUtil.availability(source: "/Volumes/\(ghost)/src",
                                       destination: NSTemporaryDirectory())
        XCTAssertFalse(a.ok)
        XCTAssertTrue(a.reason?.hasPrefix("source:") ?? false)
    }
}
