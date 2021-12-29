//
//  Forter.swift
//  Strawberry
//
//  Created by Alex Vaos on 12/26/21.
//

import Foundation
import os

class Forter {
    
    static func volumesList() -> [URL] {
        let volumeKeys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey]
        let paths = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: volumeKeys, options: [])
        
        return paths!
        
        
        
        if let urls = paths {
            for url in urls {
                let components = url.pathComponents
                if components.count > 1 && components[1] == "Volumes" {
                    log.info("\(url)")
                }
            }
        } else {
            log.info("No volumes found.")
        }
    }
    
    static func runOnDirectory(directoryUrl: URL) {
        let directoryContents: [URL]
        do {
            directoryContents = try FileManager.default.contentsOfDirectory(at: directoryUrl, includingPropertiesForKeys: nil) }
        catch {
            log.info("Cannot get directory contents")
            return
        }
        os_log("Directory count: \(directoryContents.count)")
        
        for file in directoryContents {
            do {
                let attr = try FileManager.default.attributesOfItem(atPath: file.path)
                let date = attr[FileAttributeKey.modificationDate] as! Date
                
                // Get Year
                let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
//                components.year
//                components.month
//
//
//                let yearFormatter = DateFormatter()
//                yearFormatter.dateFormat = "yyyy"
//                let year = yearFormatter.string(from: date)
//
//                // Get month-day
//                let monthDateFormatter = DateFormatter()
//                monthDateFormatter.dateFormat = "mm-dd"
//                let monthDay = monthDateFormatter.string(from: date)
                
                
                // Ensure Year folder exists
                let yearUrl = directoryUrl.appendingPathComponent(components.year as! String, isDirectory: true)
                if !FileManager.default.fileExists(atPath: yearUrl.absoluteString) {
                    try FileManager.default.createDirectory(at: yearUrl, withIntermediateDirectories: false)
                }
                
                // Ensure Month-Day folder exists
                let monthDayUrl = directoryUrl.appendingPathComponent("\(components.month)-\(components.day)", isDirectory: true)
                if !FileManager.default.fileExists(atPath: yearUrl.absoluteString) {
                    try FileManager.default.createDirectory(at: yearUrl, withIntermediateDirectories: false)
                }
                

            } catch {
                os_log("\(error.localizedDescription)")
            }
            
        }
    }
    
    static func runOnVolume(volume: URL) {
        log.debug("Forter.runOnVolume - \(volume.absoluteString)")
        
        let firstDirUrl = volume.appendingPathComponent("DCIM", isDirectory: true)
        log.debug("First directory: \(firstDirUrl)")

        if (FileManager.default.fileExists(atPath: firstDirUrl.absoluteString)) {
            self.runOnDirectory(directoryUrl: firstDirUrl)
        }
    }
    
    static func run() {
        log.debug("Forter.run")
        let volumes = self.volumesList()
        
        if (!(volumes.count > 0)) {
            log.info("No volumes found.")
            return
        } else {
            log.info("Volumes found: \(volumes.count)")
            
            for (index, volume) in volumes.enumerated() {
                let volumePath = volume.relativePath
                do {
                    let volumeTypeValues = try volume.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsReadOnlyKey])
                    let volumeWillRun: Bool = !volumeTypeValues.volumeIsLocal! && (volumeTypeValues.isWritable ?? false)
                    
                    log.info("\(index) \(volumePath) - Run: \(volumeWillRun)")
                    log.debug("Volume details: \( String(volumeTypeValues.isWritable ?? false) )")

                    if (volumeWillRun) {
                        self.runOnVolume(volume: volume)
                    }
                } catch {
                    log.error("Volume could not be read: \( volumePath )")
                }
            }
            
        }
    }
    
}


