import Foundation
import Darwin

/// What the configured rsync binary can actually do. Probed once per path via
/// `rsync --version` and cached — several Homebrew/Apple builds ship without
/// preallocation, and passing `--preallocate` to those is a *fatal* error.
struct RsyncCaps {
    var version: String
    var major: Int
    var minor: Int
    var prealloc: Bool
    var infoFlag: Bool   // --info=progress2 / --no-human-readable  (rsync >= 3.1)
    var mkpath: Bool      // --mkpath                                (rsync >= 3.2)

    private static var cache: [String: RsyncCaps] = [:]

    static func get(_ path: String) -> RsyncCaps {
        if let cached = cache[path] { return cached }
        let caps = probe(path)
        cache[path] = caps
        return caps
    }

    static func invalidate() { cache.removeAll() }

    private static func probe(_ path: String) -> RsyncCaps {
        let output = runVersion(path).lowercased()
        var major = 3, minor = 1
        if let r = output.range(of: #"version (\d+)\.(\d+)"#, options: .regularExpression) {
            let parts = output[r].replacingOccurrences(of: "version ", with: "").split(separator: ".")
            if parts.count >= 2 { major = Int(parts[0]) ?? 3; minor = Int(parts[1]) ?? 1 }
        }
        let atLeast: (Int, Int) -> Bool = { m, n in major > m || (major == m && minor >= n) }
        let hasOutput = !output.isEmpty
        return RsyncCaps(
            version: output.isEmpty ? "unknown" : "\(major).\(minor)",
            major: major,
            minor: minor,
            prealloc: output.contains("prealloc") && !output.contains("no prealloc"),
            infoFlag: hasOutput ? atLeast(3, 1) : true,
            mkpath: hasOutput ? atLeast(3, 2) : true
        )
    }

    private static func runVersion(_ path: String) -> String {
        guard FileManager.default.isExecutableFile(atPath: path) else { return "" }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--version"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

/// Runs a single rsync invocation for one rule, streams progress, writes a full
/// log to disk and hands back a `SyncRecord` when it finishes.
final class RsyncRunner {

    let rule: SyncRule
    let dryRun: Bool
    let startedAt = Date()
    let logFileName: String

    var onProgress: ((Double, String) -> Void)?   // fraction 0...1 (or -1 unknown), status text
    var onLog: ((String) -> Void)?
    var onFinish: ((SyncRecord) -> Void)?

    private let logURL: URL
    private var logHandle: FileHandle?
    private var process: Process?
    private var cancelled = false
    private var paused = false

    private var lineBuffer = ""
    private var stderrTail: [String] = []
    private var lastProgressLoggedAt = Date.distantPast

    // rsync --info=progress2 emits a \r line ~10x/sec; on a multi-million-file
    // tree that is a firehose. Coalesce UI callbacks to a few per second and
    // never touch the main thread per chunk.
    private let coalesceQueue = DispatchQueue(label: "com.drivesyncer.rsync.coalesce")
    private var pendingProgress: (Double, String)?
    private var pendingLog = ""
    private var flushArmed = false

    private var filesTransferred = 0
    private var bytesTransferred: Int64 = 0
    private var deletedFiles = 0

    // Liveness tracking for the "stuck at 0%" case: rsync's progress2 percentage
    // is bytes-moved / bytes-total, so a mostly-unchanged tree sits at 0% for the
    // whole run even though it is busy walking the file list.
    private var heartbeat: DispatchSourceTimer?
    private var lastOutputAt = Date()
    private var sawFirstProgress = false
    private var lastFraction: Double = -1

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()

    private static let percentRegex = try! NSRegularExpression(pattern: #"(\d{1,3})%"#)
    private static let chkRegex     = try! NSRegularExpression(pattern: #"(ir|to)-chk=(\d+)/(\d+)"#)
    private static let xfrRegex     = try! NSRegularExpression(pattern: #"xfr#(\d+)"#)

    init(rule: SyncRule, dryRun: Bool) {
        self.rule = rule
        self.dryRun = dryRun
        let safe = rule.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        logFileName = "\(Self.stamp.string(from: startedAt))_\(safe)\(dryRun ? "_dryrun" : "").log"
        logURL = Store.shared.logsDir.appendingPathComponent(logFileName)
    }

    // MARK: argument construction

    static func argumentList(for rule: SyncRule, dryRun: Bool) -> [String] {
        argumentList(for: rule, dryRun: dryRun, caps: RsyncCaps.get(Store.shared.config.rsyncPath))
    }

    /// Testable form — `caps` injected instead of probed from `Store`.
    static func argumentList(for rule: SyncRule, dryRun: Bool, caps: RsyncCaps) -> [String] {
        let o = rule.options

        var args: [String] = ["-r", "-l", "-t"]
        if o.preservePermissions { args.append("-p") }

        args += ["--partial", "--stats", "--modify-window=1"]
        if caps.mkpath { args.append("--mkpath") }
        if caps.infoFlag {
            args += ["--info=progress2,stats2,flist0", "--no-human-readable"]
        }

        if o.wholeFile                         { args.append("--whole-file") }
        if o.preallocate && caps.prealloc      { args.append("--preallocate") }
        if o.inPlace                           { args.append("--inplace") }
        if o.stayOnSourceFilesystem { args.append("--one-file-system") }
        if let modeFlag = o.mode.rsyncFlag { args.append(modeFlag) }

        if o.bandwidthLimitMBps > 0 {
            let v = o.bandwidthLimitMBps
            let s = v == v.rounded() ? String(Int(v)) : String(v)
            args.append("--bwlimit=\(s)m")
        }

        for pattern in o.excludes {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { args.append("--exclude=\(trimmed)") }
        }
        for arg in o.extraArgs {
            let a = arg.trimmingCharacters(in: .whitespaces)
            if a.isEmpty { continue }
            // Only Move mode is ever allowed to delete from the source, even if
            // the user typed a source-removing flag into Extra arguments.
            if o.mode != .move,
               a == "--remove-source-files" || a == "--remove-source-dirs" {
                continue
            }
            args.append(a)
        }

        if dryRun { args.append("--dry-run") }

        var src = (rule.source as NSString).standardizingPath
        if !src.hasSuffix("/") { src += "/" }               // copy contents, not the folder itself
        args.append(src)
        args.append((rule.destination as NSString).standardizingPath)
        return args
    }

    static func previewCommand(for rule: SyncRule, dryRun: Bool) -> String {
        let parts = [Store.shared.config.rsyncPath] + argumentList(for: rule, dryRun: dryRun)
        return parts.map { token -> String in
            // For `--flag=value`, quote only the value so it reads like a
            // hand-written command: `--exclude='._*'`, not `'--exclude=._*'`.
            if token.hasPrefix("--"), let eq = token.firstIndex(of: "=") {
                let flag = token[...eq]
                return flag + shellQuote(String(token[token.index(after: eq)...]))
            }
            return shellQuote(token)
        }.joined(separator: " ")
    }

    private static func shellQuote(_ s: String) -> String {
        guard !s.isEmpty else { return "''" }
        guard s.rangeOfCharacter(from: CharacterSet(charactersIn: " \t\n\"'$*?()[]{}|&;<>`\\~#")) != nil
        else { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: lifecycle

    func cancel() {
        cancelled = true
        if paused { _ = resume() }
        process?.terminate()
    }

    /// Suspend the local rsync process without interrupting its transfer state.
    func pause() -> Bool {
        guard let process, process.isRunning, process.processIdentifier > 0,
              kill(process.processIdentifier, SIGSTOP) == 0 else { return false }
        paused = true
        return true
    }

    /// Continue a process previously suspended with `pause()`.
    func resume() -> Bool {
        guard let process, process.isRunning, process.processIdentifier > 0,
              kill(process.processIdentifier, SIGCONT) == 0 else { return false }
        paused = false
        return true
    }

    func start() {
        let binary = Store.shared.config.rsyncPath
        let args = Self.argumentList(for: rule, dryRun: dryRun)

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try? FileHandle(forWritingTo: logURL)
        logHandle = log
        appendLog(log, """
        Strawberry — \(rule.name)
        started : \(startedAt)
        dry run : \(dryRun)
        command : \(Self.previewCommand(for: rule, dryRun: dryRun))

        """)

        // Creating the destination is left to `rsync --mkpath` (>= 3.2). Doing it
        // here meant a FileManager call on a possibly-spun-down HDD on the main
        // thread every run; only fall back for an ancient rsync without --mkpath.
        if !RsyncCaps.get(binary).mkpath {
            try? FileManager.default.createDirectory(
                atPath: (rule.destination as NSString).standardizingPath,
                withIntermediateDirectories: true)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        if rule.options.lowPriority { proc.qualityOfService = .utility }

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.lastOutputAt = Date()
            // Progress spam is parsed here and NOT written to the log or the live
            // view; ingestStdout routes real lines (stats, info) to disk itself.
            if let text = String(data: data, encoding: .utf8) {
                self?.ingestStdout(text)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.lastOutputAt = Date()
            try? log?.write(contentsOf: data)
            if let text = String(data: data, encoding: .utf8) {
                self?.emitLog(text)
                for piece in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                    let line = piece.trimmingCharacters(in: .whitespaces)
                    if !line.isEmpty {
                        self?.stderrTail.append(line)
                        if let count = self?.stderrTail.count, count > 12 {
                            self?.stderrTail.removeFirst(count - 12)
                        }
                    }
                }
            }
        }

        proc.terminationHandler = { [weak self] finished in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            let restOut = outPipe.fileHandleForReading.availableData
            if !restOut.isEmpty, let text = String(data: restOut, encoding: .utf8) {
                self?.ingestStdout(text)
            }
            let restErr = errPipe.fileHandleForReading.availableData
            if !restErr.isEmpty {
                try? log?.write(contentsOf: restErr)
                if let text = String(data: restErr, encoding: .utf8) { self?.emitLog(text) }
            }
            self?.complete(exitCode: finished.terminationStatus,
                           reason: finished.terminationReason,
                           log: log)
        }

        process = proc
        do {
            try proc.run()
        } catch {
            appendLog(log, "\nfailed to launch rsync: \(error)\n")
            try? log?.close()
            emit(SyncRecord(ruleID: rule.id, ruleName: rule.name,
                            startedAt: startedAt, finishedAt: Date(),
                            status: .failed, exitCode: -1,
                            filesTransferred: 0, bytesTransferred: 0, deletedFiles: 0,
                            dryRun: dryRun,
                            message: "Could not launch rsync at \(binary)",
                            logFileName: logFileName))
            return
        }

        applyLowPriorityIfNeeded(pid: proc.processIdentifier)
        emitProgress(-1, "Starting…")
        startHeartbeat()
    }

    /// While rsync is quiet, keep the UI honest: say "Preparing…" before the
    /// first progress line, and warn if output stops entirely for a while.
    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, let proc = self.process,
                  proc.isRunning, !self.paused, !self.cancelled else { return }
            let idle = Date().timeIntervalSince(self.lastOutputAt)
            if idle >= 45 {
                let mins = Int(idle / 60)
                let ago = mins >= 1 ? "\(mins) min" : "\(Int(idle))s"
                self.emitProgress(self.lastFraction,
                                  "No activity for \(ago) — the drive may be busy, or a permission prompt is waiting")
            } else if !self.sawFirstProgress {
                self.emitProgress(-1, "Preparing… \(Int(Date().timeIntervalSince(self.startedAt)))s")
            }
        }
        timer.resume()
        heartbeat = timer
    }

    // MARK: helpers

    private func applyLowPriorityIfNeeded(pid: Int32) {
        guard rule.options.lowPriority, pid > 0 else { return }
        setpriority(PRIO_PROCESS, id_t(pid), 5)                  // mild CPU nice
        let candidates = ["/usr/sbin/taskpolicy", "/usr/bin/taskpolicy"]
        guard let taskpolicy = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        let tp = Process()
        tp.executableURL = URL(fileURLWithPath: taskpolicy)
        // Disk I/O at the "utility" tier: yields to foreground work but is NOT
        // the "-b" background band, which hard-throttles to ~200 KB/s and makes
        // a large sync look stuck.
        tp.arguments = ["-d", "utility", "-p", String(pid)]
        tp.standardOutput = Pipe()
        tp.standardError = Pipe()
        try? tp.run()
    }

    private func write(_ log: FileHandle?, _ string: String) {
        if let data = string.data(using: .utf8) { try? log?.write(contentsOf: data) }
    }

    private func appendLog(_ log: FileHandle?, _ string: String) {
        write(log, string)
        emitLog(string)
    }

    private func ingestStdout(_ chunk: String) {
        lineBuffer += chunk
        while let idx = lineBuffer.firstIndex(where: { $0 == "\r" || $0 == "\n" }) {
            let line = String(lineBuffer[lineBuffer.startIndex..<idx])
            lineBuffer.removeSubrange(lineBuffer.startIndex...idx)
            if !line.isEmpty { parse(line: line) }
        }
    }

    private func parse(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // rsync --info=progress2 line, e.g.
        //   "1,234  12%   3.4MB/s   0:00:07 (xfr#8, to-chk=910/4042)"
        if trimmed.contains("%") {
            let ns = NSRange(trimmed.startIndex..., in: trimmed)
            var byteFraction = 0.0
            if let m = Self.percentRegex.firstMatch(in: trimmed, range: ns),
               let r = Range(m.range(at: 1), in: trimmed), let v = Double(trimmed[r]) {
                byteFraction = min(max(v / 100.0, 0), 1)
            }

            var checked: (done: Int, total: Int)?
            var stillScanning = false
            if let m = Self.chkRegex.firstMatch(in: trimmed, range: ns),
               let kindR = Range(m.range(at: 1), in: trimmed),
               let remR = Range(m.range(at: 2), in: trimmed),
               let totR = Range(m.range(at: 3), in: trimmed),
               let remaining = Int(trimmed[remR]), let total = Int(trimmed[totR]), total > 0 {
                checked = (max(total - remaining, 0), total)
                stillScanning = (trimmed[kindR] == "ir")   // list still being built
            }

            if let m = Self.xfrRegex.firstMatch(in: trimmed, range: ns),
               let r = Range(m.range(at: 1), in: trimmed), let n = Int(trimmed[r]) {
                filesTransferred = max(filesTransferred, n)
            }

            sawFirstProgress = true

            // Percentage: prefer "files checked" (reliable across a scan-heavy
            // run) and take whichever of that / bytes-moved is further along.
            if stillScanning {
                let found = checked?.total ?? 0
                emitProgress(-1, found > 0 ? "Scanning… \(found.formatted()) files" : "Scanning…")
            } else if let c = checked {
                let fileFraction = Double(c.done) / Double(c.total)
                let fraction = max(byteFraction, fileFraction)
                let text = "\(c.done.formatted())/\(c.total.formatted()) files"
                    + (filesTransferred > 0 ? " · \(filesTransferred.formatted()) copied" : "")
                // Keep it indeterminate until there's a real fraction — otherwise
                // a big in-sync tree sits at "0%" and strobes against the "ir-chk"
                // scan lines that report -1.
                emitProgress(fraction >= 0.01 ? fraction : -1, text)
            } else {
                emitProgress(byteFraction >= 0.01 ? byteFraction : -1, tidy(trimmed))
            }

            // Progress lines are not logged verbatim (there can be millions of
            // them); drop one breadcrumb into the log every 30s.
            let now = Date()
            if now.timeIntervalSince(lastProgressLoggedAt) >= 30 {
                lastProgressLoggedAt = now
                writeToLog("  … \(tidy(trimmed))\n")
            }
            return
        }

        if let n = statNumber("Number of regular files transferred:", trimmed) {
            filesTransferred = Int(n)
        } else if filesTransferred == 0, let n = statNumber("Number of files transferred:", trimmed) {
            filesTransferred = Int(n)
        } else if let n = statNumber("Number of deleted files:", trimmed) {
            deletedFiles = Int(n)
        } else if let n = statNumber("Total transferred file size:", trimmed) {
            bytesTransferred = n
        }

        // A real (non-progress) line: keep it in the log and the live view.
        writeToLog(line + "\n")
        emitLog(line + "\n")
    }

    private func writeToLog(_ string: String) {
        if let data = string.data(using: .utf8) { try? logHandle?.write(contentsOf: data) }
    }

    private func statNumber(_ label: String, _ line: String) -> Int64? {
        guard line.hasPrefix(label) else { return nil }
        var digits = ""
        var started = false
        for ch in line.dropFirst(label.count) {
            if ch.isNumber { digits.append(ch); started = true }
            else if ch == "," { continue }
            else if ch == " " && !started { continue }
            else { break }
        }
        return digits.isEmpty ? nil : Int64(digits)
    }

    /// The trailing rsync line is usually the generic "rsync error: … (code N)"
    /// summary. Prefer the specific line above it (the actual `failed:` / denial).
    static func bestFailureLine(_ lines: [String]) -> String? {
        let telling = lines.last {
            let l = $0.lowercased()
            return l.contains("permission denied") || l.contains("operation not permitted")
                || l.contains("failed:") || l.contains("no such file") || l.contains("cannot ")
                || l.contains("read-only")
        }
        return telling ?? lines.last
    }

    private func tidy(_ s: String) -> String {
        s.replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: "  ")
    }

    private func complete(exitCode: Int32, reason: Process.TerminationReason, log: FileHandle?) {
        heartbeat?.cancel()
        heartbeat = nil
        if !lineBuffer.isEmpty { parse(line: lineBuffer); lineBuffer = "" }
        appendLog(log, "\n\nexit code: \(exitCode)\n")
        try? log?.close()

        let status: SyncStatusKind
        switch exitCode {
        case 0:
            status = .success
        case 23, 24:                       // partial attrs / vanished source files
            status = .warning
        case 20, 30:                       // interrupted by signal / timeout
            status = cancelled ? .cancelled : .failed
        default:
            status = (reason == .uncaughtSignal && cancelled) ? .cancelled : .failed
        }

        let message: String
        switch status {
        case .success, .warning:
            let size = ByteCountFormatter.string(fromByteCount: bytesTransferred, countStyle: .file)
            var m = dryRun ? "Dry run — " : ""
            m += "\(filesTransferred) file\(filesTransferred == 1 ? "" : "s") · \(size)"
            if deletedFiles > 0 { m += " · \(deletedFiles) deleted" }
            if rule.options.mode == .move && !dryRun { m += " · copied files removed from source" }
            if exitCode == 23 { m += " · some attributes not copied" }
            if exitCode == 24 { m += " · some files vanished" }
            message = m
        case .cancelled:
            message = "Cancelled"
        case .failed:
            message = Self.bestFailureLine(stderrTail) ?? "rsync exited with code \(exitCode)"
        case .running:
            message = ""
        }

        emit(SyncRecord(ruleID: rule.id, ruleName: rule.name,
                        startedAt: startedAt, finishedAt: Date(),
                        status: status, exitCode: exitCode,
                        filesTransferred: filesTransferred,
                        bytesTransferred: bytesTransferred,
                        deletedFiles: deletedFiles,
                        dryRun: dryRun,
                        message: message,
                        logFileName: logFileName))
    }

    private func emit(_ record: SyncRecord) {
        flushCoalesced(sync: true)
        DispatchQueue.main.async { [onFinish] in onFinish?(record) }
    }

    // MARK: coalesced UI callbacks (progress / log)

    private func emitProgress(_ fraction: Double, _ text: String) {
        if fraction >= 0 { lastFraction = fraction }
        coalesceQueue.async { [weak self] in
            self?.pendingProgress = (fraction, text)
            self?.armFlush()
        }
    }

    private func emitLog(_ text: String) {
        coalesceQueue.async { [weak self] in
            guard let self else { return }
            self.pendingLog += text
            if self.pendingLog.utf8.count > 128_000 {
                self.pendingLog = String(self.pendingLog.suffix(48_000))
            }
            self.armFlush()
        }
    }

    /// Must be called on `coalesceQueue`.
    private func armFlush() {
        guard !flushArmed else { return }
        flushArmed = true
        coalesceQueue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.flushCoalesced(sync: false)
        }
    }

    private func flushCoalesced(sync: Bool) {
        let body = { [weak self] in
            guard let self else { return }
            self.flushArmed = false
            let progress = self.pendingProgress
            let log = self.pendingLog
            self.pendingProgress = nil
            self.pendingLog = ""
            guard progress != nil || !log.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let progress { self.onProgress?(progress.0, progress.1) }
                if !log.isEmpty { self.onLog?(log) }
            }
        }
        if sync { coalesceQueue.sync(execute: body) } else { coalesceQueue.async(execute: body) }
    }
}
