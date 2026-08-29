import AppKit
import ServiceManagement
import UserNotifications

// MARK: - Launch at login

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t update Login Items"
            alert.informativeText = """
            \(error.localizedDescription)

            Launch at login works once Strawberry.app has been moved to /Applications and opened once from there.
            """
            alert.runModal()
        }
    }
}

// MARK: - Folder picker

enum PanelHelper {
    static func activateApp() {
        if #available(macOS 14, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }
    }

    static func chooseDirectory(title: String, start: String?) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = title
        if let start, FileManager.default.fileExists(atPath: start) {
            panel.directoryURL = URL(fileURLWithPath: start)
        }
        activateApp()
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func chooseFile(title: String, start: String?) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = title
        if let start { panel.directoryURL = URL(fileURLWithPath: start) }
        activateApp()
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

// MARK: - Best-effort user notifications

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func report(_ record: SyncRecord) {
        guard !record.dryRun else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            switch record.status {
            case .failed:
                content.title = "Sync failed — \(record.ruleName)"
            case .warning:
                content.title = "Sync finished with warnings — \(record.ruleName)"
            case .success:
                content.title = "Synced \(record.ruleName)"
            default:
                return
            }
            content.body = record.message
            let request = UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}

// MARK: - Failure dialog

enum SyncFailureAlert {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Modal alert with the failing run's log. No-op unless the run actually
    /// failed and the user hasn't turned the dialog off.
    static func present(_ record: SyncRecord) {
        guard record.status == .failed, Store.shared.config.showFailureDialog else { return }

        let logURL = record.logFileName.map { Store.shared.logsDir.appendingPathComponent($0) }
        let raw = logURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Sync failed — \(record.ruleName)"
        var info = """
        \(record.message)

        Started \(dateFormatter.string(from: record.startedAt)) · ran \(durationText(record.duration)) · rsync exit code \(record.exitCode)
        """
        if let hint = permissionHint(record: record, log: raw) { info += "\n\n\(hint)" }
        alert.informativeText = info

        if logURL != nil {
            let body = raw.isEmpty ? "(log file could not be read)" : raw
            alert.accessoryView = logView(String(body.suffix(64_000)))
            alert.addButton(withTitle: "Open Log")
            alert.addButton(withTitle: "Dismiss")
        } else {
            alert.addButton(withTitle: "Dismiss")
        }

        PanelHelper.activateApp()
        let response = alert.runModal()
        if let logURL, response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(logURL)
        }
    }

    private static func permissionHint(record: SyncRecord, log: String) -> String? {
        let haystack = (record.message + "\n" + log).lowercased()
        guard haystack.contains("permission denied") || haystack.contains("operation not permitted")
            || record.exitCode == 3
        else { return nil }
        return "This looks like a macOS access issue. Grant Strawberry access in "
            + "System Settings ▸ Privacy & Security ▸ Full Disk Access (add Strawberry.app), "
            + "then run the sync again."
    }

    private static func logView(_ text: String) -> NSView {
        let size = NSSize(width: 560, height: 300)
        let textView = NSTextView(frame: NSRect(origin: .zero, size: size))
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.autoresizingMask = [.width]

        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView

        // The interesting part (the error, the exit code) is at the end.
        DispatchQueue.main.async { textView.scrollToEndOfDocument(nil) }
        return scroll
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }
}
