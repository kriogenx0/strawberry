//
//  USBWatcherHandler.swift
//  Strawberry
//
//  Created by Alex Vaos on 1/22/22.
//

import Foundation
import AppKit

class USBWatcherHandler: USBWatcherDelegate {
    private var usbWatcher: USBWatcher!
    init() {
        usbWatcher = USBWatcher(delegate: self)
    }

    func deviceAdded(_ device: io_object_t) {
        let message = "device added: \(device.name() ?? "<unknown>")"
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    func deviceRemoved(_ device: io_object_t) {
        let message = "device removed: \(device.name() ?? "<unknown>")"
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
