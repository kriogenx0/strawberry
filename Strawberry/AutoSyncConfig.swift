//
//  AutoSyncConfig.swift
//  Strawberry
//

import Foundation

struct AutoSyncConfig: Codable, Identifiable {
    let id: UUID
    var sourceURL: URL
    var destinationURL: URL
    var isEnabled: Bool

    init(id: UUID = UUID(), sourceURL: URL, destinationURL: URL, isEnabled: Bool = true) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.isEnabled = isEnabled
    }

    var displayName: String {
        return sourceURL.lastPathComponent
    }
}

class AutoSyncStore {
    static let shared = AutoSyncStore()

    private let userDefaultsKey = "autoSyncConfigs"

    var configs: [AutoSyncConfig] {
        get {
            guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
                  let decoded = try? JSONDecoder().decode([AutoSyncConfig].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            }
        }
    }

    func add(source: URL, destination: URL) {
        var current = configs
        current.append(AutoSyncConfig(sourceURL: source, destinationURL: destination))
        configs = current
    }

    func delete(id: UUID) {
        configs = configs.filter { $0.id != id }
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        var current = configs
        if let index = current.firstIndex(where: { $0.id == id }) {
            current[index].isEnabled = enabled
        }
        configs = current
    }
}
