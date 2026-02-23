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

        statusBarMenu.addItem(NSMenuItem.separator())

        statusBarMenu.addItem(
            withTitle: "Quit",
            action: #selector(AppDelegate.quit),
            keyEquivalent: ""
        )
    }

    // Rebuild the drive list each time the menu opens so it stays current
    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusBarMenu {
            buildMenu()
        }
    }
}
