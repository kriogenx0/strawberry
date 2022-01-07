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
    static let videoFileExtensions = ["mp4", "mp5", "mpeg", "mov", "flv", "f4v", "avchd", "avi", "mkv", "heif", "hevc", "lrv", "thm"]
    
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
        
        var filesOrganized = 0
        
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
                // log.debug("Skipping file: \(secondFolderName)")
                continue
            }
            
            // Check for Year folder
            let range = NSRange(location: 0, length: secondFolderName.utf16.count)
            let matches = self.regex.matches(in: secondFolderName, options: [], range: range)
            // log.info("Matches: \(matches.count)")
            if (matches.count > 0) {
                // log.debug("Skipping year folder: \(secondFolderName)")
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
                
                let fileLongName = "\(secondFolderName)/\(fileName)"
                
                log.info("Organizing file: \(fileLongName)")
                
                // Get attributes
                var attr: [FileAttributeKey : Any]
                do {
                    attr = try FileManager.default.attributesOfItem(atPath: fileUrl.relativePath)
                } catch {
                    log.info("Could not get attributes for file \(fileLongName): \(error.localizedDescription)")
                    continue
                }
                
//                log.debug("Attributes: \(attr  as AnyObject)")
//                dump(attr)
                
                let modifiedDate = attr[FileAttributeKey.modificationDate] as! Date
                let createdDate = attr[FileAttributeKey.creationDate] as! Date
                log.debug("File dates - created: \(createdDate), modified: \(modifiedDate.description)")
                
                let date = createdDate < modifiedDate ? createdDate : modifiedDate
                
                // Get Year & Month-day
                // let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
                // let year = String(components.year!)
                // let monthDay = "\(components.month!)-\(components.day!)"

                let yearFormatter = DateFormatter()
                yearFormatter.dateFormat = "yyyy"
                let year = yearFormatter.string(from: date)

                // Get month-day
                let monthDateFormatter = DateFormatter()
                monthDateFormatter.dateFormat = "MM-dd"
                let monthDay = monthDateFormatter.string(from: date)
                
                // Ensure Year folder exists
                // TODO: cache the creation of this folder, so future file disk checks don't need to happen
                let yearUrl = directoryUrl.appendingPathComponent(year)
                if !FileManager.default.fileExists(atPath: yearUrl.relativePath) {
                    do {
                        try FileManager.default.createDirectory(at: yearUrl, withIntermediateDirectories: false)
                    } catch {
                        log.error("Could not create directory: \(yearUrl.relativePath)")
                        return
                    }
                }
                
                // Ensure Month-Day folder exists
                let monthDayUrl = yearUrl.appendingPathComponent(monthDay, isDirectory: true)
                if !FileManager.default.fileExists(atPath: monthDayUrl.relativePath) {
                    do {
                        try FileManager.default.createDirectory(at: monthDayUrl, withIntermediateDirectories: false)
                    } catch {
                        log.error("Could not create directory: \(monthDayUrl.relativePath)")
                        return
                    }
                }
                
                // Check if file is a video file
                let formatFolderName = videoFileExtensions.contains(fileUrl.pathExtension.lowercased()) ? "\(secondFolderName)-video" : secondFolderName
                
                // Ensure format folder exists
                let formatFolderUrl = monthDayUrl.appendingPathComponent(formatFolderName, isDirectory: true)
                if !FileManager.default.fileExists(atPath: formatFolderUrl.relativePath) {
                    do {
                        try FileManager.default.createDirectory(at: formatFolderUrl, withIntermediateDirectories: false)
                    } catch {
                        log.error("Could not create directory: \(formatFolderUrl.relativePath)")
                        return
                    }
                }
                
                
                // Move file
                let destinationFileUrl = formatFolderUrl.appendingPathComponent(fileName, isDirectory: false)
                do {
                    try FileManager.default.moveItem(at: fileUrl, to: destinationFileUrl)
                } catch {
                    log.error("Could not move file: \(fileUrl.relativePath)")
                    continue
                }
                
                log.info("Moved file: \(fileUrl.relativePath) to \(destinationFileUrl.relativePath)")
                filesOrganized += 1
                
            }
            
            
        }
        
        log.info("Files organized: \(filesOrganized)")
         
    }
    
    static func runOnVolume(volume: URL) {
        // log.debug("Forter.runOnVolume - \(volume.absoluteString)")
        
        let firstDirUrl = volume.appendingPathComponent("DCIM", isDirectory: true)
        // log.debug("First directory: \(firstDirUrl)")

        if (FileManager.default.fileExists(atPath: firstDirUrl.relativePath)) {
            self.runOnDirectory(directoryUrl: firstDirUrl)
        } else {
            // log.debug("Directory does not exist \(firstDirUrl)")
        }
    }
    
    static func run() {
        log.debug("Forter.run")
        let volumes = self.volumesList()
        
        if (!(volumes.count > 0)) {
            log.info("No volumes found.")
            return
        } else {
            log.debug("Volumes found: \(volumes.count)")
            
            // Loop through each
            // for (index, volume) in volumes.enumerated() {
            for volume in volumes {
                // let volumePath = volume.relativePath
                let volumeIsSystem = volume.pathComponents.count < 2 || volume.pathComponents[1] != "Volumes"
                // log.info("\(index) \(volumePath) - System: \( String( volumeIsSystem ) )")

                if (!volumeIsSystem) {
                    self.runOnVolume(volume: volume)
                }
            }
        }
    }
    
}


