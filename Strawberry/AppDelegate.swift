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
        
        _ = MenuBarController(statusBarItem)
        
        // let usbWatcher = USBWatcher(delegate: self)
        self.usbWatcher = USBWatcherHandler()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // Menubar Actions
    @objc func organizeAllVolumes(sender: NSStatusItem) {
        Forter.runOnAllVolumes()
    }
    
    @objc func runOnDirectory(_ sender: Any) {
        var fileUrl: URL?

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK {
            fileUrl = panel.url
        }
        
        print(fileUrl?.absoluteString ?? "No file path")
        
        if let fileUrlUnwrapped = fileUrl {
            Forter.runOnDirectory(directoryUrl: fileUrlUnwrapped)
            Forter.showInFinder(url: fileUrlUnwrapped)
        }
    }
    
    @objc func quit(_ sender: Any) {
        NSApp.terminate(nil)
    }
}

