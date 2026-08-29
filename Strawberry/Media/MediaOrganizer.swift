//
//  MediaOrganizer.swift
//  Strawberry
//
//  Created by Alex Vaos on 12/26/21.
//
//  Sorts a camera card's DCIM folder in place into Year / MM-DD / <camera-folder>
//  buckets. Files in a camera folder are grouped into "events": a new event
//  (and folder) starts only when the gap to the previous shot exceeds the
//  configured Media Event Gap, so a shoot that runs past midnight stays in one
//  folder dated by when it started.
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

    /// For a list of timestamps **sorted ascending**, returns the "event start"
    /// timestamp each item belongs to: a new event begins whenever the gap from
    /// the previous item exceeds `gap` seconds. `gap <= 0` disables grouping, so
    /// each item keeps its own timestamp (one folder per calendar day). Pure.
    static func eventStartDates(forSorted dates: [Date], gap: TimeInterval) -> [Date] {
        guard gap > 0, var anchor = dates.first else { return dates }
        var previous = anchor
        var starts: [Date] = []
        starts.reserveCapacity(dates.count)
        for (i, date) in dates.enumerated() {
            if i > 0, date.timeIntervalSince(previous) > gap { anchor = date }
            starts.append(anchor)
            previous = date
        }
        return starts
    }

    static func runOnDirectory(directoryUrl: URL) {
        log.info("runOnDirectory \(directoryUrl)")

        let gap = max(0, Store.shared.config.mediaEventGapHours) * 3600

        let topLevel: [String]
        do {
            topLevel = try FileManager.default.contentsOfDirectory(atPath: directoryUrl.relativePath)
        } catch {
            log.critical("Cannot get directory contents. \(error.localizedDescription)")
            return
        }
        log.info("Directory entries: \(topLevel.count)")

        struct Item { let name: String; let url: URL; let isVideo: Bool; let date: Date }
        var filesOrganized = 0

        for folderName in topLevel {
            let folderUrl = directoryUrl.appendingPathComponent(folderName)

            var isDirectory = ObjCBool(false)
            FileManager.default.fileExists(atPath: folderUrl.relativePath, isDirectory: &isDirectory)
            if !isDirectory.boolValue { continue }

            // Skip folders that already look like a Year bucket we created.
            let range = NSRange(location: 0, length: folderName.utf16.count)
            if !yearRegex.matches(in: folderName, options: [], range: range).isEmpty { continue }

            let names: [String]
            do {
                names = try FileManager.default.contentsOfDirectory(atPath: folderUrl.relativePath)
            } catch {
                log.critical("Cannot get directory contents of \(folderName). \(error.localizedDescription)")
                continue
            }

            // Collect this folder's files with timestamps, then order by time so
            // consecutive shots can be split into events by the gap between them.
            var items: [Item] = []
            for fileName in names {
                let fileUrl = folderUrl.appendingPathComponent(fileName)

                var fileIsDirectory = ObjCBool(false)
                guard FileManager.default.fileExists(atPath: fileUrl.relativePath, isDirectory: &fileIsDirectory),
                      !fileIsDirectory.boolValue else { continue }

                guard let attr = try? FileManager.default.attributesOfItem(atPath: fileUrl.relativePath),
                      let modified = attr[.modificationDate] as? Date,
                      let created = attr[.creationDate] as? Date else {
                    log.info("Could not get attributes for file \(folderName)/\(fileName)")
                    continue
                }
                items.append(Item(name: fileName, url: fileUrl,
                                  isVideo: isVideoFile(fileUrl.pathExtension),
                                  date: min(created, modified)))
            }
            guard !items.isEmpty else { continue }

            items.sort { $0.date < $1.date }
            let eventStarts = eventStartDates(forSorted: items.map(\.date), gap: gap)
            log.info("Organizing \(items.count) file(s) in \(folderName)")

            for (item, eventStart) in zip(items, eventStarts) {
                let relative = relativeDestination(for: eventStart,
                                                   sourceFolder: folderName,
                                                   isVideo: item.isVideo)
                let destinationDirUrl = directoryUrl.appendingPathComponent(relative, isDirectory: true)

                do {
                    try FileManager.default.createDirectory(at: destinationDirUrl, withIntermediateDirectories: true)
                } catch {
                    log.error("Could not create directory: \(destinationDirUrl.relativePath)")
                    return
                }

                let destinationFileUrl = destinationDirUrl.appendingPathComponent(item.name, isDirectory: false)
                do {
                    try FileManager.default.moveItem(at: item.url, to: destinationFileUrl)
                } catch {
                    log.error("Could not move file: \(item.url.relativePath)")
                    continue
                }

                log.info("Moved file: \(item.url.relativePath) to \(destinationFileUrl.relativePath)")
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
