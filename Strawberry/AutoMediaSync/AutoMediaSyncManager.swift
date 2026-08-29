//
//  AutoMediaSyncManager.swift
//  Strawberry
//
//  When a DCIM card mounts and Auto Media Sync is configured + enabled, this
//  organizes the card in place and then rsyncs its DCIM folder to the
//  destination. A copy — the card is never emptied. Separate from Sync Rules.
//

import Foundation
import os

final class AutoMediaSyncManager {
    static let shared = AutoMediaSyncManager()

    private(set) var isSyncing = false
    private(set) var transferLog = ""

    var hasTransferLog: Bool { !transferLog.isEmpty }
    var onSyncStateChanged: (() -> Void)?
    var onOutputReceived: ((String) -> Void)?

    /// Called when a volume mounts. If Auto Media Sync is configured + enabled and
    /// the volume has a DCIM folder, organizes it then rsyncs to the destination.
    func checkAndSyncForMountedVolume(_ volumeURL: URL) {
        guard let config = AutoMediaSyncStore.shared.config, config.isEnabled else { return }
        guard MediaOrganizer.canRunOnVolume(volume: volumeURL) else { return }

        let sourceURL = volumeURL.appendingPathComponent("DCIM", isDirectory: true)

        DispatchQueue.main.async {
            self.transferLog = ""
            self.isSyncing = true
            self.notifyStateChanged()
        }

        DispatchQueue.global(qos: .utility).async {
            MediaOrganizer.runOnVolume(volume: volumeURL)
            self.runRsync(source: sourceURL, destination: config.destinationURL)
            DispatchQueue.main.async {
                self.isSyncing = false
                self.notifyStateChanged()
            }
        }
    }

    private func notifyStateChanged() {
        onSyncStateChanged?()
        NotificationCenter.default.post(name: .dsRunStateChanged, object: nil)
    }

    private func runRsync(source: URL, destination: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Store.shared.config.rsyncPath)
        // -a: archive (recursive + preserve metadata)
        // -u: update (skip files that are newer on the receiver)
        // -v: verbose (log each transferred file)
        process.arguments = ["-auv", "--", source.path + "/", destination.path + "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.transferLog += text
                self?.onOutputReceived?(text)
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            log.info("Auto Media Sync rsync finished: \(source.path) → \(destination.path), exit code \(process.terminationStatus)")
        } catch {
            log.error("Auto Media Sync rsync failed to start: \(error.localizedDescription)")
        }
    }
}
