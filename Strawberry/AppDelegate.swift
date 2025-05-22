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

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        _ = MenuBarController(statusBarItem)
        
        // let usbWatcher = USBWatcher(delegate: self)
        // Forter.run()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    
    @objc func quit(_ sender: Any) {
        NSApp.terminate(nil)
    }
    
    @objc func organizeAllVolumes(sender: NSStatusItem) {
        Forter.run()
    }
    
    @objc func runOnDirectory(_ sender: Any) {
        var filename: String = ""
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK {
            filename = panel.url?.lastPathComponent ?? "<none>"
        }
        
        print(filename)
    }
}

