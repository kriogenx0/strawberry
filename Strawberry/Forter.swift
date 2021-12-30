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
        /*
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
        */
    }
    
    static let regex = try! NSRegularExpression(pattern: "\\d{4}")
    
    static func runOnDirectory(directoryUrl: URL) {
        log.info("runOnDirectory \(directoryUrl)")
        
        let firstDirFiles: [String]
        do {
            firstDirFiles = try FileManager.default.contentsOfDirectory(atPath: directoryUrl.relativePath)
        } catch {
            log.critical("Cannot get directory contents. \(error.localizedDescription)")
            return
        }
        log.info("Directory files: \(firstDirFiles.count)")
        
        
        // 2nd directory contents
        for secondFolderName in firstDirFiles {
//            log.info("Loading file \(secondFolderName)")
            
            let secondFolderUrl = directoryUrl.appendingPathComponent(secondFolderName)
            // log.info("Checking file \(secondFolderUrl.relativePath)")
            
            // Check for directory
            var isDirectory = ObjCBool(false)
            FileManager.default.fileExists(atPath: secondFolderUrl.relativePath, isDirectory: &isDirectory)
            // log.info("is dir \(isDirectory)")
            if !isDirectory.boolValue {
                log.debug("Skipping file: \(secondFolderName)")
                continue
            }
            
            // Check for Year folder
            let range = NSRange(location: 0, length: secondFolderName.utf16.count)
            let matches = self.regex.matches(in: secondFolderName, options: [], range: range)
            // log.info("Matches: \(matches.count)")
            if (matches.count > 0) {
                log.debug("Skipping year folder: \(secondFolderName)")
                continue
            }
            
            log.info("Organizing folder \(secondFolderUrl.relativePath)")
            
            // Loop through final folder contents
            var secondFolderFiles: [String]
            do {
                secondFolderFiles = try FileManager.default.contentsOfDirectory(atPath: secondFolderUrl.relativePath)
            } catch {
                log.critical("Cannot get directory contents of \(secondFolderName). \(error.localizedDescription)")
                continue
            }
            
            for fileName in secondFolderFiles {
                let fileUrl = secondFolderUrl.appendingPathComponent(fileName)
                
                // Skip folders
                var fileIsDirectory = ObjCBool(false)
                let fileExists = FileManager.default.fileExists(atPath: fileUrl.relativePath, isDirectory: &fileIsDirectory)
                if !fileExists {
                    log.debug("File does not exist: \(fileUrl.relativePath)")
                    continue
                }
                if fileIsDirectory.boolValue {
                    log.debug("Skipping folder: \(fileName)")
                    continue
                }
                
                log.info("Organizing file: \(secondFolderName)/\(fileName)")
                
                
                
                // Get attributes
                var attr: [FileAttributeKey : Any]
                do {
                    attr = try FileManager.default.attributesOfItem(atPath: fileUrl.relativePath)
                } catch {
                    log.info("Could not get attributes: \(error.localizedDescription)")
                    continue
                }
                
//                log.debug("Attributes: \(attr  as AnyObject)")
                dump(attr)
            }
            
            
            
        
            
            
            
            
            
            /*
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
            */
            
            
            
        }
         
    }
    
    static func runOnVolume(volume: URL) {
        log.debug("Forter.runOnVolume - \(volume.absoluteString)")
        
        let firstDirUrl = volume.appendingPathComponent("DCIM", isDirectory: true)
        log.debug("First directory: \(firstDirUrl)")

        if (FileManager.default.fileExists(atPath: firstDirUrl.relativePath)) {
            self.runOnDirectory(directoryUrl: firstDirUrl)
        } else {
            log.critical("Directory does not exist \(firstDirUrl)")
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
//                do {
////                    let volumeTypeValues = try volume.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsReadOnlyKey])
////                    let volumeWillRun: Bool = !volumeTypeValues.volumeIsLocal! && (volumeTypeValues.isWritable ?? false)
//
//                } catch {
//                    log.error("Volume could not be read: \( volumePath )")
//                }
                    
                let volumeIsSystem = volume.pathComponents.count == 1 || (volume.pathComponents.indices.contains(1) && volume.pathComponents[1] == "System")
                
//                log.info("\(index) \(volumePath) - System: \( String( volumeIsSystem ) )")

                if (!volumeIsSystem) {
                    log.info("\(index) \(volumePath) - System: \( String( volumeIsSystem ) )")
                    self.runOnVolume(volume: volume)
                }
            }
            
        }
    }
    
}


