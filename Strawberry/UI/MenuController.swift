import AppKit

/// The menu-bar item and its dropdown. Rebuilt from `Store` every time it opens.
/// Idle: the Strawberry icon. While a sync runs: the spinning cycle icon.
final class MenuController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private var syncTimer: Timer?
    private var syncAngle: CGFloat = 0

    private let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        refreshButton()

        for name: Notification.Name in [.dsConfigChanged, .dsHistoryChanged, .dsRunStateChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(refreshButton),
                                                  name: name, object: nil)
        }
    }

    // MARK: status-bar button

    private var appliedTitle: String?

    @objc private func refreshButton() {
        guard let button = statusItem.button else { return }
        let scheduler = Scheduler.shared

        // A steady label — no live percentage. rsync's byte-percent bounces around
        // 0-2% for the whole file-list scan of a big tree, which made the title
        // strobe. The spinning icon shows it's working; the dropdown has detail.
        let title: String?
        if let id = scheduler.runningRuleID {
            let name = Store.shared.config.rules.first { $0.id == id }?.name ?? "Sync"
            title = scheduler.isPaused ? " \(name) — paused" : " \(name)…"
        } else if AutoMediaSyncManager.shared.isSyncing {
            title = " Importing…"
        } else {
            title = nil
        }

        guard title != appliedTitle else { return }   // no-op on repeat posts
        appliedTitle = title

        if let title {
            button.title = title
            button.imagePosition = .imageLeading
            startSyncAnimation()
        } else {
            stopSyncAnimation()
            button.title = ""
            button.image = Self.strawberryIcon()
            button.imagePosition = .imageOnly
        }
    }

    private static func strawberryIcon() -> NSImage? {
        let image = NSImage(named: "menubar-on")
        image?.size = NSSize(width: 18, height: 18)
        return image
    }

    // MARK: sync animation

    private func startSyncAnimation() {
        guard syncTimer == nil else { return }
        syncAngle = 0
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.advanceSyncAnimation()
        }
    }

    private func stopSyncAnimation() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    private func advanceSyncAnimation() {
        guard let button = statusItem.button,
              let base = NSImage(systemSymbolName: "arrow.2.circlepath", accessibilityDescription: "Syncing")
        else { return }

        syncAngle += 20
        if syncAngle >= 360 { syncAngle -= 360 }

        let size = NSSize(width: 18, height: 18)
        base.size = size
        let rotated = NSImage(size: size, flipped: false) { _ in
            let transform = NSAffineTransform()
            transform.translateX(by: size.width / 2, yBy: size.height / 2)
            transform.rotate(byDegrees: self.syncAngle)
            transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
            transform.concat()
            base.draw(in: NSRect(origin: .zero, size: size))
            return true
        }
        rotated.isTemplate = true
        button.image = rotated
    }

    // MARK: menu build

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let cfg = Store.shared.config
        let scheduler = Scheduler.shared

        // --- Media (photo organizing) -----------------------------------------
        menu.addItem(actionItem("Organize Media…", #selector(openOrganizeMedia)))
        menu.addItem(.separator())

        // --- Auto Media Sync ----------------------------------------------------
        let ams = AutoMediaSyncManager.shared
        if ams.hasTransferLog {
            menu.addItem(actionItem(ams.isSyncing ? "Show Transfer…" : "Show Last Transfer…",
                                    #selector(showAutoMediaSyncTransfer)))
        }
        if let amsConfig = AutoMediaSyncStore.shared.config {
            let item = NSMenuItem(title: "Auto Media Sync", action: nil, keyEquivalent: "")
            let sub = NSMenu()

            let cards = MediaOrganizer.volumesList().filter { MediaOrganizer.canRunOnVolume(volume: $0) }
            let fromText = cards.isEmpty
                ? "any mounted card with a DCIM folder"
                : cards.map { $0.lastPathComponent }.joined(separator: ", ")
            sub.addItem(disabledItem("From:  \(fromText)"))
            sub.addItem(disabledItem("To:      \(amsConfig.destinationURL.path)"))
            sub.addItem(.separator())

            let toggle = actionItem(amsConfig.isEnabled ? "Enabled" : "Enable", #selector(toggleAutoMediaSync))
            toggle.state = amsConfig.isEnabled ? .on : .off
            sub.addItem(toggle)
            sub.addItem(.separator())
            sub.addItem(actionItem("Change Destination…", #selector(changeAutoMediaSyncDestination)))
            sub.addItem(actionItem("Reveal Destination in Finder", #selector(revealAutoMediaSyncDestination)))
            sub.addItem(actionItem("Turn Off Auto Media Sync", #selector(removeAutoMediaSync)))
            item.submenu = sub
            menu.addItem(item)
        } else {
            menu.addItem(actionItem("Set Up Auto Media Sync…", #selector(setUpAutoMediaSync)))
        }
        menu.addItem(.separator())

        // --- Running sync ---------------------------------------------------------
        if let id = scheduler.runningRuleID {
            let name = cfg.rules.first { $0.id == id }?.name ?? ""
            let header = scheduler.isPaused
                ? "Paused \(name)"
                : scheduler.runningProgress >= 0
                ? "Syncing \(name) — \(Int(scheduler.runningProgress * 100))%"
                : "Syncing \(name)…"
            menu.addItem(disabledItem(header))
            if !scheduler.runningText.isEmpty {
                menu.addItem(disabledItem("   " + scheduler.runningText))
            }
            menu.addItem(actionItem(scheduler.isPaused ? "Resume Current Sync" : "Pause Current Sync",
                                    scheduler.isPaused ? #selector(resumeCurrent) : #selector(pauseCurrent)))
            menu.addItem(actionItem("Cancel Current Sync", #selector(cancelCurrent)))
            menu.addItem(.separator())
        }

        // --- Sync rules --------------------------------------------------------
        if cfg.rules.isEmpty {
            menu.addItem(disabledItem("No sync rules yet"))
        } else {
            for rule in cfg.rules { menu.addItem(ruleItem(rule)) }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Add Sync Rule…", #selector(addRule)))
        let runDue = actionItem("Run All Due Rules Now", #selector(runAllDue))
        runDue.isEnabled = scheduler.runningRuleID == nil && !cfg.rules.isEmpty
        menu.addItem(runDue)
        let syncLog = actionItem(scheduler.runningRuleID != nil ? "Live Sync Log…" : "Last Sync Log…",
                                 #selector(showLiveLog))
        syncLog.isEnabled = scheduler.runningRuleID != nil || !Store.shared.history.isEmpty
        menu.addItem(syncLog)
        menu.addItem(actionItem("Sync History…", #selector(showHistory)))
        menu.addItem(.separator())

        menu.addItem(actionItem("Preferences…", #selector(openPreferences)))

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Strawberry", #selector(quit)))
    }

    private func ruleItem(_ rule: SyncRule) -> NSMenuItem {
        let scheduler = Scheduler.shared
        let running = scheduler.runningRuleID == rule.id
        let availability = VolumeMonitor.shared.cached(source: rule.source, destination: rule.destination)

        let glyph: String
        if running                          { glyph = "🔄" }
        else if !rule.enabled               { glyph = "⚫️" }
        else if !availability.ok            { glyph = "⚪️" }
        else if rule.lastStatus == .failed  { glyph = "🔴" }
        else if rule.lastStatus == .warning { glyph = "🟡" }
        else                                { glyph = "🟢" }

        let item = NSMenuItem(title: "\(glyph)  \(rule.name)", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        sub.addItem(disabledItem("From:  \(rule.source.isEmpty ? "—" : rule.source)"))
        sub.addItem(disabledItem("To:      \(rule.destination.isEmpty ? "—" : rule.destination)"))
        sub.addItem(disabledItem("Schedule:  \(rule.interval.label)"))

        if running {
            let pct = scheduler.runningProgress >= 0 ? " \(Int(scheduler.runningProgress * 100))%" : ""
            sub.addItem(disabledItem(scheduler.isPaused ? "Status:  paused" : "Status:  syncing\(pct)"))
        } else if !availability.ok {
            sub.addItem(disabledItem("Status:  unavailable — \(availability.reason ?? "")"))
        } else if !rule.enabled {
            sub.addItem(disabledItem("Status:  disabled"))
        } else {
            if let last = rule.lastRunAt {
                let outcome = rule.lastStatus?.label ?? ""
                sub.addItem(disabledItem("Last run:  \(relative.localizedString(for: last, relativeTo: Date())) — \(outcome)"))
            } else {
                sub.addItem(disabledItem("Last run:  never"))
            }
            sub.addItem(disabledItem("Next:  \(nextDueText(rule))"))
        }

        sub.addItem(.separator())

        let idle = scheduler.runningRuleID == nil
        let syncNow = actionItem("Sync Now", #selector(syncRuleNow(_:)), represent: rule.id)
        syncNow.isEnabled = idle && availability.ok
        sub.addItem(syncNow)

        let dry = actionItem("Dry Run (preview changes)", #selector(dryRunRule(_:)), represent: rule.id)
        dry.isEnabled = idle && availability.ok
        sub.addItem(dry)

        sub.addItem(.separator())
        let lastLog = actionItem("Show Last Log", #selector(showLastLog(_:)), represent: rule.id)
        lastLog.isEnabled = Store.shared.history.contains { $0.ruleID == rule.id && $0.logFileName != nil }
        sub.addItem(lastLog)
        sub.addItem(.separator())
        sub.addItem(actionItem(rule.enabled ? "Disable Rule" : "Enable Rule",
                               #selector(toggleRuleEnabled(_:)), represent: rule.id))
        sub.addItem(actionItem("Edit…", #selector(editRule(_:)), represent: rule.id))
        sub.addItem(actionItem("Reveal Source in Finder", #selector(revealSource(_:)), represent: rule.id))
        sub.addItem(actionItem("Reveal Destination in Finder", #selector(revealDestination(_:)), represent: rule.id))
        sub.addItem(.separator())
        sub.addItem(actionItem("Delete Rule…", #selector(deleteRule(_:)), represent: rule.id))

        item.submenu = sub
        return item
    }

    private func nextDueText(_ rule: SyncRule) -> String {
        let base = rule.lastSuccessAt ?? .distantPast
        guard let due = rule.interval.nextDue(after: base) else { return "manual only" }
        if due <= Date() { return "due now" }
        return relative.localizedString(for: due, relativeTo: Date())
    }

    // MARK: item factories

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ selector: Selector, represent: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.representedObject = represent
        return item
    }

    private func rule(from sender: Any?) -> SyncRule? {
        guard let item = sender as? NSMenuItem, let id = item.representedObject as? UUID else { return nil }
        return Store.shared.config.rules.first { $0.id == id }
    }

    private func reveal(_ path: String) {
        // fileExists() can stall on a spun-down drive — keep it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let url = URL(fileURLWithPath: path)
            let target = FileManager.default.fileExists(atPath: path) ? url : url.deletingLastPathComponent()
            DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([target]) }
        }
    }

    // MARK: media actions

    @objc private func openOrganizeMedia() { WindowManager.shared.openOrganizeMedia() }

    // MARK: Auto Media Sync actions

    @objc private func setUpAutoMediaSync() {
        let info = NSAlert()
        info.messageText = "Set Up Auto Media Sync"
        info.informativeText = "Auto Media Sync automatically organizes any mounted card that has a DCIM folder and copies it to the folder you choose."
        info.addButton(withTitle: "Choose Folder…")
        info.addButton(withTitle: "Cancel")
        PanelHelper.activateApp()
        guard info.runModal() == .alertFirstButtonReturn,
              let dest = chooseAutoMediaSyncDestination() else { return }
        AutoMediaSyncStore.shared.set(destination: dest)
        NotificationCenter.default.post(name: .dsConfigChanged, object: nil)
    }

    @objc private func changeAutoMediaSyncDestination() {
        guard let dest = chooseAutoMediaSyncDestination() else { return }
        AutoMediaSyncStore.shared.set(destination: dest)
        NotificationCenter.default.post(name: .dsConfigChanged, object: nil)
    }

    @objc private func toggleAutoMediaSync() {
        let current = AutoMediaSyncStore.shared.config?.isEnabled ?? false
        AutoMediaSyncStore.shared.setEnabled(!current)
        NotificationCenter.default.post(name: .dsConfigChanged, object: nil)
    }

    @objc private func removeAutoMediaSync() {
        AutoMediaSyncStore.shared.remove()
        NotificationCenter.default.post(name: .dsConfigChanged, object: nil)
    }

    @objc private func revealAutoMediaSyncDestination() {
        if let url = AutoMediaSyncStore.shared.config?.destinationURL { reveal(url.path) }
    }

    @objc private func showAutoMediaSyncTransfer() {
        PanelHelper.activateApp()
        TransferWindowController.shared.showWindow(nil)
        TransferWindowController.shared.window?.orderFrontRegardless()
    }

    private func chooseAutoMediaSyncDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Select Destination Folder"
        panel.prompt = "Set Destination"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        PanelHelper.activateApp()
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: sync actions

    @objc private func cancelCurrent() { Scheduler.shared.cancelCurrent() }
    @objc private func pauseCurrent()  { Scheduler.shared.pauseCurrent() }
    @objc private func resumeCurrent() { Scheduler.shared.resumeCurrent() }
    @objc private func showLiveLog()   { WindowManager.shared.openLiveLog() }
    @objc private func addRule()       { WindowManager.shared.openEditor(rule: nil) }
    @objc private func runAllDue()     { Scheduler.shared.runAllDue() }
    @objc private func showHistory()   { WindowManager.shared.openHistory() }
    @objc private func showLastLog(_ sender: Any?) {
        guard let r = rule(from: sender),
              let record = Store.shared.history.first(where: { $0.ruleID == r.id && $0.logFileName != nil }),
              let name = record.logFileName else { return }
        NSWorkspace.shared.open(Store.shared.logsDir.appendingPathComponent(name))
    }
    @objc private func openPreferences() { WindowManager.shared.openPreferences() }
    @objc private func quit()            { NSApp.terminate(nil) }

    @objc private func syncRuleNow(_ sender: Any?) {
        if let r = rule(from: sender) { Scheduler.shared.triggerManual(ruleID: r.id, dryRun: false) }
    }
    @objc private func dryRunRule(_ sender: Any?) {
        if let r = rule(from: sender) { Scheduler.shared.triggerManual(ruleID: r.id, dryRun: true) }
    }
    @objc private func editRule(_ sender: Any?) {
        if let r = rule(from: sender) { WindowManager.shared.openEditor(rule: r) }
    }
    @objc private func revealSource(_ sender: Any?) {
        if let r = rule(from: sender) { reveal(r.source) }
    }
    @objc private func revealDestination(_ sender: Any?) {
        if let r = rule(from: sender) { reveal(r.destination) }
    }
    @objc private func toggleRuleEnabled(_ sender: Any?) {
        guard var r = rule(from: sender) else { return }
        r.enabled.toggle()
        Store.shared.upsert(rule: r)
    }
    @objc private func deleteRule(_ sender: Any?) {
        guard let r = rule(from: sender) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(r.name)”?"
        alert.informativeText = "This removes the sync rule only. Files already copied to the destination are left untouched."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        PanelHelper.activateApp()
        if alert.runModal() == .alertFirstButtonReturn {
            Store.shared.deleteRule(id: r.id)
        }
    }
}
