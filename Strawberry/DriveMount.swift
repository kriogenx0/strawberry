//
//  DriveMount.swift
//  Strawberry
//
//  Created by Alex Vaos on 5/24/25.
//

import Foundation
import FileKit

// 1. Set up File System Events
let fileManager = FileManager.default

let directoryToMonitor = "/Volumes/MyDrive" // Change this to your desired mount point
//let directoryToMonitor = "/Volumes/MyDrive/" // Change this to your desired mount point


// Create a custom FileEventDelegate to handle events
class FileEventDelegate: NSObject, FSMonitor {
    let fileManager: FileManager
    
    init(fileManager: FileManager) {
        self.fileManager = fileManager
        super.init()
    }
    
    func fileSystemEvent(event: FileEvent) {
        // 2. Detect Drive Mount
        if event.type == .mount {
            print("Drive mounted at: \(event.path)")
            // 3. Run the Application
            runApplication(path: "/Applications/YourApp.app") // Replace with your app's path
        } else if event.type == .unmount {
            print("Drive unmounted at: \(event.path)")
        }
    }
    
    func runApplication(path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [] // Add any arguments your app needs
        
        do {
            try process.run()
        } catch {
            print("Error running app: \(error)")
        }
    }
    
    func driveMounted(event: FileEvent) {
        
    }
}

let delegate = FileEventDelegate(fileManager: fileManager)
fileManager.startMonitoringDirectory(atPath: directoryToMonitor, delegate: delegate)

//RunLoop.current.run() // Keep the app running to listen for events
