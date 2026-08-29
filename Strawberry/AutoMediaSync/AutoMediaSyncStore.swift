//
//  AutoMediaSyncStore.swift
//  Strawberry
//
//  Persistence for Auto Media Sync: a single destination folder that every
//  mounted DCIM card is organized into and copied to. Distinct from Sync Rules.
//

import Foundation

struct AutoMediaSyncConfig: Codable {
    var destinationURL: URL
    var isEnabled: Bool

    init(destinationURL: URL, isEnabled: Bool = true) {
        self.destinationURL = destinationURL
        self.isEnabled = isEnabled
    }

    var displayName: String {
        destinationURL.lastPathComponent
    }
}

final class AutoMediaSyncStore {
    static let shared = AutoMediaSyncStore()

    // Same key the pre-merge "AutoSync" used, so an existing setting keeps working.
    private let userDefaultsKey = "autoSyncDestination"

    var config: AutoMediaSyncConfig? {
        get {
            guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
                  let decoded = try? JSONDecoder().decode(AutoMediaSyncConfig.self, from: data) else {
                return nil
            }
            return decoded
        }
        set {
            if let value = newValue, let data = try? JSONEncoder().encode(value) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }

    func set(destination: URL) {
        config = AutoMediaSyncConfig(destinationURL: destination)
    }

    func remove() {
        config = nil
    }

    func setEnabled(_ enabled: Bool) {
        config?.isEnabled = enabled
    }
}
