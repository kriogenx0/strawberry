//
//  MediaOrganizer.swift
//  Strawberry
//
//  Created by Alex Vaos on 12/26/21.
//
//  Sorts a camera card's DCIM folder in place into Year / MM-DD / <camera-folder>
//  buckets, moving each file by its earliest of (created, modified) date.
//

import Foundation
import os
import AppKit

enum MediaOrganizer {

    static func volumesList() -> [URL] {
        let volumeKeys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey]
        return FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: volumeKeys, options: []) ?? []
    }

    static let yearRegex = try! NSRegularExpression(pattern: "\\d{4}")
    static let videoFileExtensions = ["mp4", "mp5", "mpeg", "mov", "flv", "f4v", "avchd", "avi", "mkv", "heif", "hevc", "lrv", "thm"]

    static func isVideoFile(_ pathExtension: String) -> Bool {
        videoFileExtensions.contains(pathExtension.lowercased())
    }

    /// Where a file taken on `date` from camera folder `sourceFolder` should live,
    /// relative to the DCIM directory being organized. Pure — no filesystem.
    static func relativeDestination(for date: Date, sourceFolder: String, isVideo: Bool) -> String {
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let year = yearFormatter.string(from: date)

        let monthDayFormatter = DateFormatter()
        monthDayFormatter.dateFormat = "MM-dd"
        let monthDay = monthDayFormatter.string(from: date)

        let formatFolder = isVideo ? "\(sourceFolder)-video" : sourceFolder
        return "\(year)/\(monthDay)/\(formatFolder)"
    }

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

        for secondFolderName in firstDirFiles {
            let secondFolderUrl = directoryUrl.appendingPathComponent(secondFolderName)

            var isDirectory = ObjCBool(false)
            FileManager.default.fileExists(atPath: secondFolderUrl.relativePath, isDirectory: &isDirectory)
            if !isDirectory.boolValue { continue }

            // Skip folders that already look like a Year bucket we created.
            let range = NSRange(location: 0, length: secondFolderName.utf16.count)
            if !yearRegex.matches(in: secondFolderName, options: [], range: range).isEmpty { continue }

            log.info("Organizing folder \(secondFolderUrl.relativePath)")

            let secondFolderFiles: [String]
            do {
                secondFolderFiles = try FileManager.default.contentsOfDirectory(atPath: secondFolderUrl.relativePath)
            } catch {
                log.critical("Cannot get directory contents of \(secondFolderName). \(error.localizedDescription)")
                continue
            }

            for fileName in secondFolderFiles {
                let fileUrl = secondFolderUrl.appendingPathComponent(fileName)

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

                let attr: [FileAttributeKey: Any]
                do {
                    attr = try FileManager.default.attributesOfItem(atPath: fileUrl.relativePath)
                } catch {
                    log.info("Could not get attributes for file \(fileLongName): \(error.localizedDescription)")
                    continue
                }

                let modifiedDate = attr[.modificationDate] as! Date
                let createdDate = attr[.creationDate] as! Date
                let date = createdDate < modifiedDate ? createdDate : modifiedDate

                let relative = relativeDestination(for: date,
                                                   sourceFolder: secondFolderName,
                                                   isVideo: isVideoFile(fileUrl.pathExtension))
                let destinationDirUrl = directoryUrl.appendingPathComponent(relative, isDirectory: true)

                do {
                    try FileManager.default.createDirectory(at: destinationDirUrl, withIntermediateDirectories: true)
                } catch {
                    log.error("Could not create directory: \(destinationDirUrl.relativePath)")
                    return
                }

                let destinationFileUrl = destinationDirUrl.appendingPathComponent(fileName, isDirectory: false)
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

    static func canRunOnVolume(volume: URL) -> Bool {
        let dcimUrl = volume.appendingPathComponent("DCIM", isDirectory: true)
        let dcimExists = FileManager.default.fileExists(atPath: dcimUrl.relativePath)
        let volumeIsSystem = volume.pathComponents.count < 2 || volume.pathComponents[1] != "Volumes"
        return !volumeIsSystem && dcimExists
    }

    static func runOnVolume(volume: URL) {
        let dcimUrl = volume.appendingPathComponent("DCIM", isDirectory: true)
        if FileManager.default.fileExists(atPath: dcimUrl.relativePath) {
            runOnDirectory(directoryUrl: dcimUrl)
        }
    }

    static func runOnAllVolumes() {
        let volumes = volumesList()
        var volumesRan: [String] = []

        for volume in volumes where canRunOnVolume(volume: volume) {
            runOnVolume(volume: volume)
            volumesRan.append(volume.lastPathComponent)
            showInFinder(url: volume)
        }

        let message = volumesRan.isEmpty ? "No Volumes Found." : "Ran on Volumes: \(volumesRan.joined(separator: ", "))"
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    static func showInFinder(url: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}
