import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Rules / preferences changed on disk.
    static let dsConfigChanged   = Notification.Name("dsConfigChanged")
    /// A sync record was added or history cleared.
    static let dsHistoryChanged  = Notification.Name("dsHistoryChanged")
    /// The currently running sync changed state / progress.
    static let dsRunStateChanged = Notification.Name("dsRunStateChanged")
}

// MARK: - Schedule

enum SyncInterval: String, Codable, CaseIterable, Identifiable {
    case manual
    case hourly
    case sixHours
    case twelveHours
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    /// Minimum time that must elapse since the last successful sync. `nil` == manual only.
    var seconds: TimeInterval? {
        switch self {
        case .manual:      return nil
        case .hourly:      return 3600
        case .sixHours:    return 6 * 3600
        case .twelveHours: return 12 * 3600
        case .daily:       return 24 * 3600
        case .weekly:      return 7 * 24 * 3600
        case .monthly:     return nil
        }
    }

    var label: String {
        switch self {
        case .manual:      return "Manual only"
        case .hourly:      return "Every hour"
        case .sixHours:    return "Every 6 hours"
        case .twelveHours: return "Every 12 hours"
        case .daily:       return "Daily"
        case .weekly:      return "Weekly"
        case .monthly:     return "Monthly"
        }
    }

    /// The next due date. Monthly uses the calendar rather than an arbitrary
    /// 30-day duration, so it tracks real month boundaries.
    func nextDue(after lastSuccess: Date) -> Date? {
        switch self {
        case .manual:
            return nil
        case .monthly:
            return Calendar.current.date(byAdding: .month, value: 1, to: lastSuccess)
        default:
            guard let seconds else { return nil }
            return lastSuccess.addingTimeInterval(seconds)
        }
    }

    func isDue(since lastSuccess: Date, at date: Date = Date()) -> Bool {
        guard let due = nextDue(after: lastSuccess) else { return false }
        return due <= date
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SyncInterval(rawValue: raw) ?? .daily
    }
}

// MARK: - rsync options

/// What to do when a file *already exists* at the destination. A per-rule setting.
enum ExistingFilePolicy: String, Codable, CaseIterable, Identifiable {
    /// Plain rsync: copy whenever size/mtime differ, so the destination ends up
    /// identical to the source — even if that replaces a newer file there.
    case overwrite = "override"
    /// `--update` / `-u` — replace a file only when the source copy is newer.
    case update
    /// `--ignore-existing` — only ever create files that aren't there yet;
    /// never replace one that already exists.
    case addOnly

    var id: String { rawValue }

    /// Short name for a segmented control.
    var title: String {
        switch self {
        case .overwrite: return "Override"
        case .update:    return "Update"
        case .addOnly:   return "Add new only"
        }
    }

    /// One-line explanation of the selected mode.
    var detail: String {
        switch self {
        case .overwrite: return "Replace destination files whenever they differ — keeps the destination identical to the source."
        case .update:    return "Replace a file only when the source copy is newer (rsync --update)."
        case .addOnly:   return "Only copy files that don’t exist yet; an existing file is never replaced (rsync --ignore-existing)."
        }
    }

    var flag: String? {
        switch self {
        case .overwrite: return nil
        case .update:    return "--update"
        case .addOnly:   return "--ignore-existing"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExistingFilePolicy(rawValue: raw) ?? .overwrite
    }
}

struct RsyncOptions: Codable, Equatable {
    /// `--delete-during` — remove files at the destination that no longer exist in the source.
    var mirrorDelete: Bool = false
    /// `--remove-source-files` — delete each source file once it has been copied
    /// to the destination. Turns the sync into a move. Irreversible.
    var removeSourceFiles: Bool = false
    /// How to treat files that already exist at the destination.
    var existingFiles: ExistingFilePolicy = .overwrite
    /// `--whole-file` — skip the delta algorithm (a big win for local disk‑to‑disk).
    var wholeFile: Bool = true
    /// `--preallocate` — reserve the file's space up front to reduce fragmentation on HDDs.
    /// Off by default: many macOS rsync builds are compiled without prealloc support,
    /// and the flag is silently dropped unless the binary reports the capability.
    var preallocate: Bool = false
    /// `--inplace` — write updates directly into the destination file (less scratch space, not crash‑safe).
    var inPlace: Bool = false
    /// `--one-file-system` — don't descend into nested mount points.
    var stayOnSourceFilesystem: Bool = false
    /// keep `-p`; when false pass `--no-perms` (useful for exFAT/FAT destinations).
    var preservePermissions: Bool = true
    /// `taskpolicy -d utility` + a soft `nice` + `.utility` QoS so a background
    /// sync yields disk & CPU to foreground apps.
    var lowPriority: Bool = true
    /// `--bwlimit` in MB/s. 0 = no limit. A hard cap on transfer throughput —
    /// the most direct way to keep a sync from saturating a slow disk.
    var bandwidthLimitMBps: Double = 0
    var excludes: [String] = RsyncOptions.defaultExcludes
    var extraArgs: [String] = []

    static let defaultExcludes: [String] = [
        "._*",
        ".!*",
        ".dropbox*",
        ".DS_Store",
        ".Spotlight*",
        "Thumbs.db",
        ".BridgeCache*",
        "_no_sync",
        "_no_redundancy",
        "-no_redundancy",
        ".AppleDB",
        ".com.apple.timemachine.supported",
        ".dbfseventsd",
        ".DocumentRevisions*",
        ".fseventsd",
        ".TemporaryItems",
        ".vol",
        ".Trash*",
        ".VolumeIcon.icns",
        "$RECYCLE.BIN",
        "System Volume Information",
    ]

    init() {}

    enum CodingKeys: String, CodingKey {
        case mirrorDelete, removeSourceFiles, existingFiles, wholeFile, preallocate, inPlace
        case stayOnSourceFilesystem, preservePermissions, lowPriority
        case bandwidthLimitMBps, excludes, extraArgs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RsyncOptions()
        mirrorDelete           = try c.decodeIfPresent(Bool.self,      forKey: .mirrorDelete)           ?? d.mirrorDelete
        removeSourceFiles      = try c.decodeIfPresent(Bool.self,      forKey: .removeSourceFiles)      ?? d.removeSourceFiles
        existingFiles          = try c.decodeIfPresent(ExistingFilePolicy.self, forKey: .existingFiles) ?? d.existingFiles
        wholeFile              = try c.decodeIfPresent(Bool.self,      forKey: .wholeFile)              ?? d.wholeFile
        preallocate            = try c.decodeIfPresent(Bool.self,      forKey: .preallocate)            ?? d.preallocate
        inPlace                = try c.decodeIfPresent(Bool.self,      forKey: .inPlace)                ?? d.inPlace
        stayOnSourceFilesystem = try c.decodeIfPresent(Bool.self,      forKey: .stayOnSourceFilesystem) ?? d.stayOnSourceFilesystem
        preservePermissions    = try c.decodeIfPresent(Bool.self,      forKey: .preservePermissions)    ?? d.preservePermissions
        lowPriority            = try c.decodeIfPresent(Bool.self,      forKey: .lowPriority)            ?? d.lowPriority
        bandwidthLimitMBps     = try c.decodeIfPresent(Double.self,    forKey: .bandwidthLimitMBps)     ?? d.bandwidthLimitMBps
        excludes               = try c.decodeIfPresent([String].self,  forKey: .excludes)               ?? d.excludes
        extraArgs              = try c.decodeIfPresent([String].self,  forKey: .extraArgs)              ?? d.extraArgs
    }
}

// MARK: - Rule

enum SyncStatusKind: String, Codable {
    case success
    case warning
    case failed
    case cancelled
    case running

    var label: String {
        switch self {
        case .success:   return "Success"
        case .warning:   return "Completed with warnings"
        case .failed:    return "Failed"
        case .cancelled: return "Cancelled"
        case .running:   return "Running"
        }
    }

    var emoji: String {
        switch self {
        case .success:   return "🟢"
        case .warning:   return "🟡"
        case .failed:    return "🔴"
        case .cancelled: return "⚪️"
        case .running:   return "🔄"
        }
    }
}

struct SyncRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var source: String
    var destination: String
    var interval: SyncInterval = .daily
    var enabled: Bool = true
    var options: RsyncOptions = RsyncOptions()

    var lastSuccessAt: Date? = nil
    var lastRunAt: Date? = nil
    var lastStatus: SyncStatusKind? = nil

    init(name: String, source: String, destination: String) {
        self.name = name
        self.source = source
        self.destination = destination
    }

    enum CodingKeys: String, CodingKey {
        case id, name, source, destination, interval, enabled, options
        case lastSuccessAt, lastRunAt, lastStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(UUID.self,           forKey: .id)            ?? UUID()
        name          = try c.decodeIfPresent(String.self,         forKey: .name)          ?? "Rule"
        source        = try c.decodeIfPresent(String.self,         forKey: .source)        ?? ""
        destination   = try c.decodeIfPresent(String.self,         forKey: .destination)   ?? ""
        interval      = try c.decodeIfPresent(SyncInterval.self,   forKey: .interval)      ?? .daily
        enabled       = try c.decodeIfPresent(Bool.self,           forKey: .enabled)       ?? true
        options       = try c.decodeIfPresent(RsyncOptions.self,   forKey: .options)       ?? RsyncOptions()
        lastSuccessAt = try c.decodeIfPresent(Date.self,           forKey: .lastSuccessAt)
        lastRunAt     = try c.decodeIfPresent(Date.self,           forKey: .lastRunAt)
        lastStatus    = try c.decodeIfPresent(SyncStatusKind.self, forKey: .lastStatus)
    }
}

// MARK: - History

struct SyncRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var ruleID: UUID
    var ruleName: String
    var startedAt: Date
    var finishedAt: Date
    var status: SyncStatusKind
    var exitCode: Int32
    var filesTransferred: Int
    var bytesTransferred: Int64
    var deletedFiles: Int
    var dryRun: Bool
    var message: String
    var logFileName: String?

    var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
}

// MARK: - Config

struct AppConfig: Codable {
    var rules: [SyncRule] = []
    var rsyncPath: String = "/opt/homebrew/bin/rsync"
    var launchAtLogin: Bool = false
    var historyLimit: Int = 500
    /// Pop a modal with the run's log when a sync ends in `.failed`.
    var showFailureDialog: Bool = true

    init() {}

    enum CodingKeys: String, CodingKey {
        case rules, rsyncPath, launchAtLogin, historyLimit, showFailureDialog
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules             = try c.decodeIfPresent([SyncRule].self, forKey: .rules)             ?? []
        rsyncPath         = try c.decodeIfPresent(String.self,     forKey: .rsyncPath)         ?? "/opt/homebrew/bin/rsync"
        launchAtLogin     = try c.decodeIfPresent(Bool.self,       forKey: .launchAtLogin)     ?? false
        historyLimit      = try c.decodeIfPresent(Int.self,        forKey: .historyLimit)      ?? 500
        showFailureDialog = try c.decodeIfPresent(Bool.self,       forKey: .showFailureDialog) ?? true
    }
}
