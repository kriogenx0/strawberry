import AppKit

/// Owns the periodic tick, the "is a sync running" state and the manual queue.
/// Runs everything serially — one rsync at a time — which is what spinning disks
/// want anyway.
final class Scheduler {
    static let shared = Scheduler()

    private(set) var runningRuleID: UUID?
    private(set) var runningProgress: Double = -1
    private(set) var runningText: String = ""
    private(set) var isPaused = false
    /// The tail of the active (or most recently finished) rsync log, for the
    /// live-log window. Cap it so a very verbose rsync cannot grow memory forever.
    private(set) var runningLogText: String = ""

    private var timer: Timer?
    private var currentJob: RsyncRunner?
    private var manualQueue: [UUID] = []
    /// True between choosing a rule and its off-main availability check returning.
    private var launching = false

    /// Minimum gap between *automatic* attempts of the same rule, whatever the
    /// outcome. A failed sync does not update `lastSuccessAt`, so without this a
    /// rule that keeps failing would be relaunched on every tick — a tight loop.
    /// Manual "Sync Now" / "Run All Due" bypass this.
    private static let autoRetryBackoff: TimeInterval = 30 * 60

    private init() {}

    /// A breadcrumb file that exists only while an rsync is actually running.
    /// The after-request git hook checks for it so `make dev` never kills a
    /// long sync out from under the user.
    static var runningLockURL: URL {
        Store.shared.baseDir.appendingPathComponent("sync-in-progress.lock")
    }
    static func writeRunningLock(ruleName: String) {
        try? ruleName.write(to: runningLockURL, atomically: true, encoding: .utf8)
    }
    static func clearRunningLock() {
        try? FileManager.default.removeItem(at: runningLockURL)
    }

    func start() {
        Self.clearRunningLock()   // clear a stale lock left by a crash / force-quit
        VolumeMonitor.shared.start()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(volumesChanged),
                             name: NSWorkspace.didMountNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(volumesChanged),
                             name: NSWorkspace.didUnmountNotification, object: nil)

        tick()
    }

    @objc private func volumesChanged() {
        NotificationCenter.default.post(name: .dsConfigChanged, object: nil)  // refresh menu glyphs
        tick()
    }

    // MARK: public triggers

    /// Queue a real sync (respected even if not "due"), or a dry run immediately when idle.
    func triggerManual(ruleID: UUID, dryRun: Bool) {
        if dryRun {
            guard currentJob == nil, runningRuleID == nil, !launching,
                  let rule = Store.shared.config.rules.first(where: { $0.id == ruleID }) else { return }
            attemptLaunch(rule: rule, dryRun: true)
            return
        }
        if !manualQueue.contains(ruleID) { manualQueue.append(ruleID) }
        tick()
    }

    func runAllDue() {
        let now = Date()
        for rule in Store.shared.config.rules where rule.enabled {
            let base = rule.lastSuccessAt ?? .distantPast
            guard rule.interval.isDue(since: base, at: now) else { continue }
            guard VolumeMonitor.shared.cached(source: rule.source, destination: rule.destination).ok else { continue }
            if !manualQueue.contains(rule.id) { manualQueue.append(rule.id) }
        }
        tick()
    }

    func pauseCurrent() {
        guard !isPaused, currentJob?.pause() == true else { return }
        isPaused = true
        runningText = "Paused"
        NotificationCenter.default.post(name: .dsRunStateChanged, object: nil)
    }

    func resumeCurrent() {
        guard isPaused, currentJob?.resume() == true else { return }
        isPaused = false
        runningText = "Resuming…"
        NotificationCenter.default.post(name: .dsRunStateChanged, object: nil)
    }

    func cancelCurrent() {
        guard currentJob != nil else { return }
        isPaused = false
        runningText = "Cancelling…"
        currentJob?.cancel()
        NotificationCenter.default.post(name: .dsRunStateChanged, object: nil)
    }

    // MARK: engine

    private func tick() {
        guard currentJob == nil, runningRuleID == nil, !launching else { return }

        // 1. anything explicitly queued
        while let id = manualQueue.first {
            manualQueue.removeFirst()
            guard let rule = Store.shared.config.rules.first(where: { $0.id == id }) else { continue }
            attemptLaunch(rule: rule, dryRun: false)
            return
        }

        // 2. the first enabled rule that is due, not in a retry-backoff window,
        //    and whose drives look present (cheap cached check)
        let now = Date()
        for rule in Store.shared.config.rules where rule.enabled {
            let base = rule.lastSuccessAt ?? .distantPast
            guard rule.interval.isDue(since: base, at: now) else { continue }
            if let lastRun = rule.lastRunAt,
               now.timeIntervalSince(lastRun) < Self.autoRetryBackoff { continue }
            guard VolumeMonitor.shared.cached(source: rule.source, destination: rule.destination).ok else { continue }
            attemptLaunch(rule: rule, dryRun: false)
            return
        }
    }

    /// Confirm the endpoints off the main thread (statfs on a spun-down HDD can
    /// block for seconds), then launch. `launching` blocks re-entrancy until the
    /// check comes back.
    private func attemptLaunch(rule: SyncRule, dryRun: Bool) {
        guard currentJob == nil, runningRuleID == nil, !launching else { return }
        launching = true
        VolumeMonitor.shared.verify(source: rule.source, destination: rule.destination) { [weak self] availability in
            guard let self else { return }
            self.launching = false
            guard self.currentJob == nil, self.runningRuleID == nil else { return }
            if availability.ok {
                self.run(rule: rule, dryRun: dryRun)
            } else {
                self.tick()   // this candidate isn't reachable; try the next
            }
        }
    }

    private func run(rule: SyncRule, dryRun: Bool) {
        // Keep this guard at the execution boundary as well as in `tick()`.
        // All work flows through this scheduler, but this prevents a future
        // trigger path from accidentally starting a second rsync.
        guard currentJob == nil, runningRuleID == nil else { return }

        runningRuleID = rule.id
        runningProgress = -1
        runningText = "Starting…"
        isPaused = false
        runningLogText = ""
        Self.writeRunningLock(ruleName: rule.name)

        let job = RsyncRunner(rule: rule, dryRun: dryRun)
        currentJob = job

        job.onProgress = { [weak self] fraction, text in
            guard let self, self.runningRuleID == rule.id, !self.isPaused else { return }
            self.runningProgress = fraction
            self.runningText = text
            NotificationCenter.default.post(name: .dsRunStateChanged, object: nil)
        }

        job.onLog = { [weak self] text in
            guard let self, self.runningRuleID == rule.id else { return }
            // RsyncRunner already coalesces these to a few per second.
            var combined = self.runningLogText + text
            let maximumLogCharacters = 200_000
            if combined.count > maximumLogCharacters {
                combined = String(combined.suffix(maximumLogCharacters))
            }
            self.runningLogText = combined
            NotificationCenter.default.post(name: .dsRunStateChanged, object: nil)
        }

        job.onFinish = { [weak self] record in
            guard let self else { return }
            Store.shared.addRecord(record)
            Store.shared.mutateConfig { cfg in
                guard let idx = cfg.rules.firstIndex(where: { $0.id == rule.id }) else { return }
                cfg.rules[idx].lastRunAt = record.finishedAt
                cfg.rules[idx].lastStatus = record.status
                if !record.dryRun && (record.status == .success || record.status == .warning) {
                    cfg.rules[idx].lastSuccessAt = record.finishedAt
                }
            }
            self.currentJob = nil
            self.runningRuleID = nil
            self.runningProgress = -1
            self.runningText = ""
            self.isPaused = false
            Self.clearRunningLock()
            NotificationCenter.default.post(name: .dsRunStateChanged, object: nil)
            Notifier.report(record)
            SyncFailureAlert.present(record)            // modal; blocks until dismissed
            DispatchQueue.main.async { self.tick() }   // pick up the next queued / due rule
        }

        NotificationCenter.default.post(name: .dsRunStateChanged, object: nil)
        job.start()
    }
}
