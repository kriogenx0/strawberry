import AppKit
import SwiftUI

/// Owns the app's auxiliary windows (rule editor, history, live log) and keeps a
/// single instance of each around.
final class WindowManager {
    static let shared = WindowManager()

    private var editor: NSWindowController?
    private var history: NSWindowController?
    private var liveLog: NSWindowController?
    private var organize: NSWindowController?
    private var preferences: NSWindowController?

    private init() {}

    func openPreferences() {
        if let preferences {
            present(preferences)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView()))
        window.title = "Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        preferences = controller
        present(controller)
    }

    func openOrganizeMedia() {
        organize?.close()

        let view = OrganizeMediaView(onClose: { [weak self] in
            self?.organize?.close()
            self?.organize = nil
        })

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Organize Media"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        organize = controller
        present(controller)
    }

    func openEditor(rule: SyncRule?) {
        editor?.close()

        let base = rule ?? SyncRule(name: "New Rule", source: "", destination: "")
        let isNew = rule == nil

        let view = RuleEditorView(
            rule: base,
            isNew: isNew,
            onSave: { [weak self] saved in
                Store.shared.upsert(rule: saved)
                self?.editor?.close(); self?.editor = nil
            },
            onCancel: { [weak self] in
                self?.editor?.close(); self?.editor = nil
            },
            onDelete: isNew ? nil : { [weak self] in
                Store.shared.deleteRule(id: base.id)
                self?.editor?.close(); self?.editor = nil
            }
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = isNew ? "New Sync Rule" : "Edit Sync Rule"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        editor = controller
        present(controller)
    }

    func openHistory() {
        if let history {
            present(history)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: HistoryView()))
        window.title = "Sync History"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 640, height: 540))
        window.center()

        let controller = NSWindowController(window: window)
        history = controller
        present(controller)
    }

    func openLiveLog() {
        if let liveLog {
            present(liveLog)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: LiveLogView()))
        window.title = "Live Sync Log"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 520))
        window.center()

        let controller = NSWindowController(window: window)
        liveLog = controller
        present(controller)
    }

    private func present(_ controller: NSWindowController) {
        PanelHelper.activateApp()
        if let window = controller.window {
            // Menu-bar app: keep these panels above other apps' windows and
            // follow the user across Spaces / into full-screen.
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.hidesOnDeactivate = false
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.orderFrontRegardless()
    }
}
