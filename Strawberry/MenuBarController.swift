//
//  MenuBarController.swift
//  Strawberry
//
//  Created by Alex Vaos on 1/15/22.
//

import Foundation
import Cocoa
import os

class MenuBarController: NSObject, NSMenuDelegate {

    static let menuIconOn = NSImage(named: NSImage.Name("menubar-on"))
    static let menuIconOff = NSImage(named: NSImage.Name("menubar-off"))

    private let statusBarItem: NSStatusItem
    private let statusBarMenu: NSMenu

    private var syncAnimationTimer: Timer?
    private var syncAnimationAngle: CGFloat = 0

    init(_ statusBarItem: NSStatusItem) {
        self.statusBarItem = statusBarItem

        let menuButton = statusBarItem.button
        menuButton?.image = MenuBarController.menuIconOn
        menuButton?.image?.size = NSSize(width: 18, height: 18)

        statusBarMenu = NSMenu(title: "Strawberry")

        super.init()

        statusBarMenu.delegate = self
        statusBarItem.menu = statusBarMenu

        buildMenu()
    }

    func buildMenu() {
        statusBarMenu.removeAllItems()

        statusBarMenu.addItem(
            withTitle: "Organize All Volumes",
            action: #selector(AppDelegate.organizeAllVolumes),
            keyEquivalent: ""
        )

        // Run on Drive submenu
        let runOnDriveItem = NSMenuItem(title: "Run on Drive", action: nil, keyEquivalent: "")
        let driveSubmenu = NSMenu(title: "Run on Drive")

        let volumes = Forter.volumesList()
        let runnableVolumes = volumes.filter { Forter.canRunOnVolume(volume: $0) }

        if runnableVolumes.isEmpty {
            let noVolumesItem = NSMenuItem(title: "No Drives Available", action: nil, keyEquivalent: "")
            noVolumesItem.isEnabled = false
            driveSubmenu.addItem(noVolumesItem)
        } else {
            for volume in runnableVolumes {
                let name = volume.lastPathComponent
                let item = NSMenuItem(title: name, action: #selector(AppDelegate.runOnDrive(_:)), keyEquivalent: "")
                item.representedObject = volume
                driveSubmenu.addItem(item)
            }
        }

        runOnDriveItem.submenu = driveSubmenu
        statusBarMenu.addItem(runOnDriveItem)

        statusBarMenu.addItem(
            withTitle: "Run on Folder...",
            action: #selector(AppDelegate.runOnFolder(_:)),
            keyEquivalent: ""
        )

        // Autosync section
        statusBarMenu.addItem(NSMenuItem.separator())

        if AutoSyncManager.shared.hasTransferLog {
            let title = AutoSyncManager.shared.isSyncing ? "Show Transfer..." : "Show Last Transfer..."
            statusBarMenu.addItem(
                withTitle: title,
                action: #selector(AppDelegate.showTransfer(_:)),
                keyEquivalent: ""
            )
        }

        if let config = AutoSyncStore.shared.config {
            let item = NSMenuItem(title: config.displayName, action: nil, keyEquivalent: "")
            item.state = .on

            let settingsMenu = NSMenu()

            let toggleItem = NSMenuItem(
                title: config.isEnabled ? "Enabled" : "Enable",
                action: #selector(AppDelegate.toggleAutoSync(_:)),
                keyEquivalent: ""
            )
            toggleItem.state = config.isEnabled ? .on : .off
            settingsMenu.addItem(toggleItem)

            let deleteItem = NSMenuItem(
                title: "Remove Autosync",
                action: #selector(AppDelegate.deleteAutoSync(_:)),
                keyEquivalent: ""
            )
            settingsMenu.addItem(deleteItem)

            item.submenu = settingsMenu
            statusBarMenu.addItem(item)
        } else {
            statusBarMenu.addItem(
                withTitle: "Add Autosync...",
                action: #selector(AppDelegate.addAutoSync(_:)),
                keyEquivalent: ""
            )
        }

        statusBarMenu.addItem(NSMenuItem.separator())

        statusBarMenu.addItem(
            withTitle: "Quit",
            action: #selector(AppDelegate.quit),
            keyEquivalent: ""
        )
    }

    // Rebuild the drive list and autosync section each time the menu opens
    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusBarMenu {
            buildMenu()
        }
    }

    // MARK: - Sync Animation

    func startSyncAnimation() {
        guard syncAnimationTimer == nil else { return }
        syncAnimationAngle = 0
        syncAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.advanceSyncAnimation()
        }
    }

    func stopSyncAnimation() {
        syncAnimationTimer?.invalidate()
        syncAnimationTimer = nil
        statusBarItem.button?.image = MenuBarController.menuIconOn
        statusBarItem.button?.image?.size = NSSize(width: 18, height: 18)
    }

    private func advanceSyncAnimation() {
        syncAnimationAngle += 20
        if syncAnimationAngle >= 360 { syncAnimationAngle -= 360 }

        guard let base = NSImage(systemSymbolName: "arrow.2.circlepath", accessibilityDescription: nil) else { return }
        let size = NSSize(width: 18, height: 18)
        base.size = size

        let rotated = NSImage(size: size, flipped: false) { _ in
            let transform = NSAffineTransform()
            transform.translateX(by: size.width / 2, yBy: size.height / 2)
            transform.rotate(byDegrees: self.syncAnimationAngle)
            transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
            transform.concat()
            base.draw(in: NSRect(origin: .zero, size: size))
            return true
        }
        statusBarItem.button?.image = rotated
    }
}
