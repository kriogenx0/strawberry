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

    // Menubar Actions
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

    @objc func quit(_ sender: Any) {
        NSApp.terminate(nil)
    }
}
