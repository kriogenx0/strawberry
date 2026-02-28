//
//  AutoSyncConfig.swift
//  Strawberry
//

import Foundation

struct AutoSyncConfig: Codable {
    var destinationURL: URL
    var isEnabled: Bool

    init(destinationURL: URL, isEnabled: Bool = true) {
        self.destinationURL = destinationURL
        self.isEnabled = isEnabled
    }

    var displayName: String {
        return destinationURL.lastPathComponent
    }
}

class AutoSyncStore {
    static let shared = AutoSyncStore()

    private let userDefaultsKey = "autoSyncDestination"

    var config: AutoSyncConfig? {
        get {
            guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
                  let decoded = try? JSONDecoder().decode(AutoSyncConfig.self, from: data) else {
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
        config = AutoSyncConfig(destinationURL: destination)
    }

    func remove() {
        config = nil
    }

    func setEnabled(_ enabled: Bool) {
        config?.isEnabled = enabled
    }
}
