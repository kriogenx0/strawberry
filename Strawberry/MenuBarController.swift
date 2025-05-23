//
//  MenuBarController.swift
//  Strawberry
//
//  Created by Alex Vaos on 1/15/22.
//

import Foundation
import Cocoa
import os

class MenuBarController {
    
    static let menuIconOn = NSImage(named: NSImage.Name("menubar-on"))
    static let menuIconOff = NSImage(named: NSImage.Name("menubar-off"))
    
    @IBOutlet weak var menuBarMenu: NSMenu!

    init(_ statusBarItem: NSStatusItem) {
        let menuButton = statusBarItem.button
        
        menuButton?.image = MenuBarController.menuIconOn
        menuButton?.image?.size = NSSize(width: 18, height: 18)
        // menuButton?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        // menuButton?.action = #selector(MenuBarController.menubarClick(sender:))
        // menuButton?.image = MenuBarController.menuIconOff
        
        let statusBarMenu = NSMenu(title: "Strawberry")
        statusBarItem.menu = statusBarMenu
        
        statusBarMenu.addItem(
            withTitle: "Organize All Volumes",
            action: #selector(AppDelegate.organizeAllVolumes),
            keyEquivalent: ""
        )
        
        statusBarMenu.addItem(
            withTitle: "Run on Directory...",
            action: #selector(AppDelegate.runOnDirectory),
            keyEquivalent: ""
        )

        statusBarMenu.addItem(
            withTitle: "Quit",
            action: #selector(AppDelegate.quit),
            keyEquivalent: ""
        )
        
    }
    
    
    /*
    @objc func menubarClick(sender: NSStatusItem) {
        let event = NSApp.currentEvent!
        if event.type == NSEvent.EventType.rightMouseDown {
            // TODO Toggle Enabled
        } else {
            sender.popUpMenu(menuBarMenu)
        }
    }
  
    @IBAction func launchAtLogin(_ sender: NSMenuItem) {
        if (sender.state == .on) {
            // let success = SMLoginItemSetEnabled(launcherBundleId as CFString, false)
        } else {

        }
    }
    */
}
