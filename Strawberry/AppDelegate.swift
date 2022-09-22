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
    
    var usbWatcher: USBWatcherHandler?
    let statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        MenuBarController(statusBarItem)
         self.usbWatcher = USBWatcherHandler()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    @objc func run(sender: NSStatusItem) {
        Forter.run()
    }
    
    @objc func quit(_ sender: Any) {
        NSApp.terminate(nil)
    }
    
}

