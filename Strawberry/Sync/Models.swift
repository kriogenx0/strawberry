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

/// How a Sync Rule reconciles the source and the destination. Unchanged files
/// (same size + timestamp) are always skipped; a changed file is always replaced.
enum SyncMode: String, Codable, CaseIterable, Identifiable {
    /// Copy new and changed files to the destination. Nothing at the destination
    /// is ever deleted, and the source is left intact. The safe default.
    case append
    /// Like Append, but also delete files at the *destination* that are gone
    /// from the source, so it ends up an exact replica (`rsync --delete`). The
    /// source is never modified.
    case mirror
    /// Copy everything, then delete each file from the source once it is safely
    /// at the destination (`rsync --remove-source-files`). The destination is
    /// never pruned. Irreversible on the source.
    case move

    var id: String { rawValue }

    /// Short name for a segmented control.
    var title: String {
        switch self {
        case .append: return "Append"
        case .mirror: return "Mirror"
        case .move:   return "Move"
        }
    }

    /// One-line explanation of the selected mode.
    var detail: String {
        switch self {
        case .append: return "Copy new and changed files to the destination. Nothing there is deleted; the source is left untouched."
        case .mirror: return "Make the destination an exact replica of the source — changed files are replaced and destination files missing from the source are deleted. The source is never touched."
        case .move:   return "Copy everything, then delete each file from the source once it is safely at the destination. The destination is never pruned."
        }
    }

    /// Terse "what happens to the source folder" line.
    var sourceEffect: String {
        switch self {
        case .append, .mirror: return "Left as-is."
        case .move:            return "Files are deleted after they copy successfully."
        }
    }

    /// Terse "what happens to the destination folder" line.
    var destinationEffect: String {
        switch self {
        case .append: return "New and changed files are copied in; extra files are kept."
        case .mirror: return "New and changed files are copied in; files not in the source are deleted."
        case .move:   return "New and changed files are copied in; nothing is deleted."
        }
    }

    /// The extra rsync flag this mode implies, if any.
    var rsyncFlag: String? {
        switch self {
        case .append: return nil
        case .mirror: return "--delete-during"
        case .move:   return "--remove-source-files"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SyncMode(rawValue: raw) ?? .append
    }
}

struct RsyncOptions: Codable, Equatable {
    /// Move / Append / Mirror. See `SyncMode`.
    var mode: SyncMode = .append
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
        case mode, wholeFile, preallocate, inPlace
        case stayOnSourceFilesystem, preservePermissions, lowPriority
        case bandwidthLimitMBps, excludes, extraArgs
        // Pre-2.0 rules stored these instead of `mode`; read only, for migration.
        case mirrorDelete, removeSourceFiles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RsyncOptions()

        if let m = try c.decodeIfPresent(SyncMode.self, forKey: .mode) {
            mode = m
        } else {
            // Migrate a pre-2.0 rule: move wins over mirror wins over append.
            let legacyMove   = (try? c.decodeIfPresent(Bool.self, forKey: .removeSourceFiles)) ?? nil ?? false
            let legacyMirror = (try? c.decodeIfPresent(Bool.self, forKey: .mirrorDelete)) ?? nil ?? false
            mode = legacyMove ? .move : (legacyMirror ? .mirror : .append)
        }

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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(wholeFile, forKey: .wholeFile)
        try c.encode(preallocate, forKey: .preallocate)
        try c.encode(inPlace, forKey: .inPlace)
        try c.encode(stayOnSourceFilesystem, forKey: .stayOnSourceFilesystem)
        try c.encode(preservePermissions, forKey: .preservePermissions)
        try c.encode(lowPriority, forKey: .lowPriority)
        try c.encode(bandwidthLimitMBps, forKey: .bandwidthLimitMBps)
        try c.encode(excludes, forKey: .excludes)
        try c.encode(extraArgs, forKey: .extraArgs)
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
    /// Media Organization groups shots into one event folder until the gap
    /// between consecutive files exceeds this many hours, so a shoot that runs
    /// past midnight stays together. 0 = off (one folder per calendar day).
    var mediaEventGapHours: Double = 8

    init() {}

    enum CodingKeys: String, CodingKey {
        case rules, rsyncPath, launchAtLogin, historyLimit, showFailureDialog, mediaEventGapHours
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules             = try c.decodeIfPresent([SyncRule].self, forKey: .rules)             ?? []
        rsyncPath         = try c.decodeIfPresent(String.self,     forKey: .rsyncPath)         ?? "/opt/homebrew/bin/rsync"
        launchAtLogin     = try c.decodeIfPresent(Bool.self,       forKey: .launchAtLogin)     ?? false
        historyLimit      = try c.decodeIfPresent(Int.self,        forKey: .historyLimit)      ?? 500
        showFailureDialog = try c.decodeIfPresent(Bool.self,       forKey: .showFailureDialog) ?? true
        mediaEventGapHours = try c.decodeIfPresent(Double.self,    forKey: .mediaEventGapHours) ?? 8
    }
}
