//
//  AutoSyncManager.swift
//  Strawberry
//

import Foundation

class AutoSyncManager {
    static let shared = AutoSyncManager()

    private(set) var isSyncing = false
    var onSyncStateChanged: (() -> Void)?

    /// Called when a volume mounts. Runs rsync for any enabled autosync configs
    /// whose destination folder lives on that volume.
    func checkAndSyncForMountedVolume(_ volumeURL: URL) {
        let enabledConfigs = AutoSyncStore.shared.configs.filter { $0.isEnabled }
        let relevant = enabledConfigs.filter { config in
            config.destinationURL.path.hasPrefix(volumeURL.path)
        }
        guard !relevant.isEmpty else { return }

        DispatchQueue.main.async {
            self.isSyncing = true
            self.onSyncStateChanged?()
        }

        DispatchQueue.global(qos: .utility).async {
            for config in relevant {
                self.runRsync(source: config.sourceURL, destination: config.destinationURL)
            }
            DispatchQueue.main.async {
                self.isSyncing = false
                self.onSyncStateChanged?()
            }
        }
    }

    private func runRsync(source: URL, destination: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        // -a: archive (recursive + preserve metadata)
        // -u: update (skip files that are newer on the receiver)
        process.arguments = ["-au", "--", source.path + "/", destination.path + "/"]
        do {
            try process.run()
            process.waitUntilExit()
            log.info("rsync finished: \(source.path) → \(destination.path), exit code \(process.terminationStatus)")
        } catch {
            log.error("rsync failed to start: \(error.localizedDescription)")
        }
    }
}
