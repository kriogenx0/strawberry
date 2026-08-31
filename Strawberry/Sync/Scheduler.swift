import AppKit

/// Owns the periodic tick, the "is a sync running" state and the manual queue.
/// Runs everything serially — one rsync at a time — which is what spinning disks
/// want anyway.
final class Scheduler {
    static let shared = Scheduler()

    private(set) var runningRuleID: UUID?

    /// Name of the rule whose rsync is currently running, if any.
    var runningRuleName: String? {
        guard let runningRuleID else { return nil }
        return Store.shared.config.rules.first { $0.id == runningRuleID }?.name
    }

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
        // A lock left behind means the last session was killed mid-sync. The
        // rsync child is a separate process and may still be finishing, so don't
        // immediately re-run a rule that will still look "due" — that stacks a
        // second copy on top of the orphan.
        let uncleanShutdown = FileManager.default.fileExists(atPath: Self.runningLockURL.path)
        Self.clearRunningLock()

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

        if uncleanShutdown {
            log.error("Scheduler: unclean shutdown detected — holding automatic syncs for 5 minutes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in self?.tick() }
        } else {
            tick()
        }
    }

    /// Best-effort clean stop when the app is quitting: SIGTERM the rsync child so
    /// it doesn't outlive the app and get a duplicate stacked on it next launch.
    func shutdown() {
        currentJob?.cancel()
        Self.clearRunningLock()
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
    /// block for seconds), then launch.
    ///
    /// `runningRuleID` is reserved *synchronously* here, before the async check —
    /// so any re-entrant `tick()` (a modal alert or `waitUntilExit` can pump the
    /// main run loop while we're mid-flight) sees the slot taken and bails
    /// instead of starting a duplicate rsync for the same rule.
    private func attemptLaunch(rule: SyncRule, dryRun: Bool) {
        guard currentJob == nil, runningRuleID == nil, !launching else { return }
        launching = true
        runningRuleID = rule.id
        runningText = "Checking drives…"

        VolumeMonitor.shared.verify(source: rule.source, destination: rule.destination) { [weak self] availability in
            guard let self else { return }
            self.launching = false
            // Still our reservation, and nothing else grabbed the job?
            guard self.currentJob == nil, self.runningRuleID == rule.id else { return }
            if availability.ok {
                self.run(rule: rule, dryRun: dryRun)
            } else {
                self.runningRuleID = nil        // release the reservation
                self.runningText = ""
                self.tick()                     // this candidate isn't reachable; try the next
            }
        }
    }

    private func run(rule: SyncRule, dryRun: Bool) {
        // Must be running against the reservation `attemptLaunch` made, with no
        // job already attached.
        guard currentJob == nil, runningRuleID == rule.id else { return }

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
            // Clear the running state FIRST so the menu-bar goes idle and nothing
            // is wedged. The failure alert is shown afterwards and off the hot
            // path — a menu-bar app's modal can end up on another Space and never
            // get dismissed, which must not freeze the scheduler.
            self.currentJob = nil
            self.runningRuleID = nil
            self.runningProgress = -1
            self.runningText = ""
            self.isPaused = false
            Self.clearRunningLock()
            NotificationCenter.default.post(name: .dsRunStateChanged, object: nil)

            Notifier.report(record)
            DispatchQueue.main.async {
                SyncFailureAlert.present(record)
                self.tick()   // pick up the next queued / due rule
            }
        }

        NotificationCenter.default.post(name: .dsRunStateChanged, object: nil)
        job.start()
    }
}
