//
//  AutoSyncManager.swift
//  Strawberry
//

import Foundation

class AutoSyncManager {
    static let shared = AutoSyncManager()

    private(set) var isSyncing = false
    private(set) var transferLog = ""

    var hasTransferLog: Bool { !transferLog.isEmpty }
    var onSyncStateChanged: (() -> Void)?
    var onOutputReceived: ((String) -> Void)?

    /// Called when a volume mounts. Runs rsync for any enabled autosync configs
    /// whose destination folder lives on that volume.
    func checkAndSyncForMountedVolume(_ volumeURL: URL) {
        let enabledConfigs = AutoSyncStore.shared.configs.filter { $0.isEnabled }
        let relevant = enabledConfigs.filter { config in
            config.destinationURL.path.hasPrefix(volumeURL.path)
        }
        guard !relevant.isEmpty else { return }

        DispatchQueue.main.async {
            self.transferLog = ""
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
            log.info("rsync finished: \(source.path) → \(destination.path), exit code \(process.terminationStatus)")
        } catch {
            log.error("rsync failed to start: \(error.localizedDescription)")
        }
    }
}
