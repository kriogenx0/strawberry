//
//  AppDelegate.swift
//  Strawberry
//
//  Created by Alex Vaos on 12/25/21.
//

import Cocoa
import os

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var menuController: MenuController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        _ = Store.shared
        menuController = MenuController()
        Scheduler.shared.start()
        Notifier.requestAuthorization()
        Store.shared.mutateConfig { $0.launchAtLogin = LoginItem.isEnabled }

        AutoMediaSyncManager.shared.onSyncStateChanged = {
            if AutoMediaSyncManager.shared.isSyncing {
                TransferWindowController.shared.clearAndShow()
            }
        }
        AutoMediaSyncManager.shared.onOutputReceived = { text in
            TransferWindowController.shared.append(text)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(volumeDidMount(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Media volumes

    /// A camera card just mounted. If Auto Media Sync is configured it takes over
    /// (organize + copy, no prompt). Otherwise, for a card not already covered by
    /// a Sync Rule, offer the one-off "organize this card's photos" action.
    @objc func volumeDidMount(_ notification: Notification) {
        guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL,
              MediaOrganizer.canRunOnVolume(volume: volumeURL) else { return }

        // Auto Media Sync handles configured cards on its own — organize + copy,
        // no prompt.
        AutoMediaSyncManager.shared.checkAndSyncForMountedVolume(volumeURL)
        if AutoMediaSyncStore.shared.config?.isEnabled == true { return }

        // If a rule already covers this volume as its source, stay quiet.
        let covered = Store.shared.config.rules.contains {
            volumeURL.path == $0.source || $0.source.hasPrefix(volumeURL.path + "/")
        }
        guard !covered else { return }

        let volumeName = volumeURL.lastPathComponent
        let alert = NSAlert()
        alert.messageText = "Drive Mounted: \(volumeName)"
        alert.informativeText = "Organize the photos on “\(volumeName)” into Year / Month-Day folders?"
        alert.addButton(withTitle: "Organize")
        alert.addButton(withTitle: "Skip")
        if alert.runModal() == .alertFirstButtonReturn {
            MediaOrganizer.runOnVolume(volume: volumeURL)
            MediaOrganizer.showInFinder(url: volumeURL)
        }
    }
}
