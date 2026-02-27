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

    let statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        menuBarController = MenuBarController(statusBarItem)

        AutoSyncManager.shared.onSyncStateChanged = { [weak self] in
            guard let self = self, let controller = self.menuBarController else { return }
            if AutoSyncManager.shared.isSyncing {
                TransferWindowController.shared.clearAndShow()
                controller.startSyncAnimation()
            } else {
                controller.stopSyncAnimation()
            }
        }

        AutoSyncManager.shared.onOutputReceived = { text in
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

    @objc func volumeDidMount(_ notification: Notification) {
        guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }

        // Trigger autosync for any configs whose destination is on this volume
        AutoSyncManager.shared.checkAndSyncForMountedVolume(volumeURL)

        guard Forter.canRunOnVolume(volume: volumeURL) else { return }

        let volumeName = volumeURL.lastPathComponent
        let alert = NSAlert()
        alert.messageText = "Drive Mounted: \(volumeName)"
        alert.informativeText = "Would you like to run Strawberry on \"\(volumeName)\"?"
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Skip")

        if alert.runModal() == .alertFirstButtonReturn {
            Forter.runOnVolume(volume: volumeURL)
            Forter.showInFinder(url: volumeURL)
        }
    }

    // MARK: - Menubar Actions

    @objc func organizeAllVolumes(sender: NSStatusItem) {
        Forter.runOnAllVolumes()
    }

    @objc func runOnDrive(_ sender: NSMenuItem) {
        guard let volumeURL = sender.representedObject as? URL else { return }
        Forter.runOnVolume(volume: volumeURL)
        Forter.showInFinder(url: volumeURL)
    }

    @objc func runOnFolder(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let folderUrl = panel.url else { return }

        Forter.runOnDirectory(directoryUrl: folderUrl)
        Forter.showInFinder(url: folderUrl)
    }

    // MARK: - Autosync Actions

    @objc func addAutoSync(_ sender: Any) {
        let sourcePanel = NSOpenPanel()
        sourcePanel.title = "Select Source Folder to Sync"
        sourcePanel.prompt = "Select Source"
        sourcePanel.allowsMultipleSelection = false
        sourcePanel.canChooseDirectories = true
        sourcePanel.canChooseFiles = false
        guard sourcePanel.runModal() == .OK, let sourceURL = sourcePanel.url else { return }

        let destPanel = NSOpenPanel()
        destPanel.title = "Select Destination Folder"
        destPanel.prompt = "Set Destination"
        destPanel.allowsMultipleSelection = false
        destPanel.canChooseDirectories = true
        destPanel.canChooseFiles = false
        destPanel.canCreateDirectories = true
        guard destPanel.runModal() == .OK, let destURL = destPanel.url else { return }

        AutoSyncStore.shared.add(source: sourceURL, destination: destURL)
    }

    @objc func toggleAutoSync(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        let current = AutoSyncStore.shared.configs.first(where: { $0.id == id })
        AutoSyncStore.shared.setEnabled(!(current?.isEnabled ?? true), for: id)
    }

    @objc func deleteAutoSync(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        AutoSyncStore.shared.delete(id: id)
    }

    @objc func showTransfer(_ sender: Any) {
        TransferWindowController.shared.showWindow(nil)
        TransferWindowController.shared.window?.orderFrontRegardless()
    }

    @objc func quit(_ sender: Any) {
        NSApp.terminate(nil)
    }
}
