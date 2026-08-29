import Foundation

/// Single source of truth for rules, preferences and sync history.
/// All access happens on the main thread.
final class Store {
    static let shared = Store()

    private(set) var config: AppConfig
    private(set) var history: [SyncRecord]

    let baseDir: URL
    let logsDir: URL
    private let configURL: URL
    private let historyURL: URL

    private init() {
        let fm = FileManager.default
        // Tests / experiments point this at a scratch dir so they can never
        // touch the real config, history or logs.
        if let override = ProcessInfo.processInfo.environment["STRAWBERRY_DATA_DIR"], !override.isEmpty {
            baseDir = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            baseDir = appSupport.appendingPathComponent("Strawberry", isDirectory: true)
        }
        logsDir    = baseDir.appendingPathComponent("logs", isDirectory: true)
        configURL  = baseDir.appendingPathComponent("config.json")
        historyURL = baseDir.appendingPathComponent("history.json")
        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let decoder = Store.makeDecoder()

        if let data = try? Data(contentsOf: configURL),
           let cfg = try? decoder.decode(AppConfig.self, from: data) {
            config = cfg
        } else {
            config = AppConfig()
        }

        if let data = try? Data(contentsOf: historyURL),
           let hist = try? decoder.decode([SyncRecord].self, from: data) {
            history = hist
        } else {
            history = []
        }

        // Make sure we point at an rsync that actually exists.
        if !fm.isExecutableFile(atPath: config.rsyncPath) {
            for candidate in ["/opt/homebrew/bin/rsync", "/usr/local/bin/rsync", "/usr/bin/rsync"]
            where fm.isExecutableFile(atPath: candidate) {
                config.rsyncPath = candidate
                break
            }
        }
    }

    // MARK: coders

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    // MARK: config mutations

    func saveConfig() {
        if let data = try? makeEncoder().encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
        NotificationCenter.default.post(name: .dsConfigChanged, object: nil)
    }

    func mutateConfig(_ block: (inout AppConfig) -> Void) {
        block(&config)
        saveConfig()
    }

    func upsert(rule: SyncRule) {
        if let idx = config.rules.firstIndex(where: { $0.id == rule.id }) {
            config.rules[idx] = rule
        } else {
            config.rules.append(rule)
        }
        saveConfig()
    }

    func deleteRule(id: UUID) {
        config.rules.removeAll { $0.id == id }
        saveConfig()
    }

    // MARK: history

    func addRecord(_ record: SyncRecord) {
        history.insert(record, at: 0)
        if history.count > max(config.historyLimit, 1) {
            history = Array(history.prefix(config.historyLimit))
        }
        persistHistory()
        NotificationCenter.default.post(name: .dsHistoryChanged, object: nil)
    }

    func clearHistory() {
        history = []
        persistHistory()
        NotificationCenter.default.post(name: .dsHistoryChanged, object: nil)
    }

    private func persistHistory() {
        if let data = try? makeEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }
}
