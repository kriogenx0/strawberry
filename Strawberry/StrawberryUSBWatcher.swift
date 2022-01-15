//
//  StrawberryUSBWatcher.swift
//  Strawberry
//
//  Created by Alex Vaos on 1/7/22.
//

import Foundation

class StrawberryUSBWatcher: USBWatcherDelegate {
    private var usbWatcher: USBWatcher!
    init() {
        usbWatcher = USBWatcher(delegate: self)
    }

    func deviceAdded(_ device: io_object_t) {
        print("device added: \(device.name() ?? "<unknown>")")
    }

    func deviceRemoved(_ device: io_object_t) {
        print("device removed: \(device.name() ?? "<unknown>")")
    }
}
