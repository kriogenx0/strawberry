import Foundation
import AppKit

/// `VolumeUtil.availability` calls `statfs`/`fileExists` on `/Volumes/<name>`,
/// which blocks for *seconds* when an external HDD is spun down. This keeps a
/// background-refreshed cache so the menu and scheduler never do that on the
/// main thread.
final class VolumeMonitor {
    static let shared = VolumeMonitor()

    private let queue = DispatchQueue(label: "com.drivesyncer.volumes", qos: .utility)
    private let lock = NSLock()
    private var cache: [String: VolumeUtil.Availability] = [:]
    private var timer: DispatchSourceTimer?

    private init() {}

    private static func key(_ source: String, _ destination: String) -> String {
        source + "\u{0}" + destination
    }

    func start() {
        queue.async { [weak self] in self?.refreshAll() }

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 15, repeating: 15)
        t.setEventHandler { [weak self] in self?.refreshAll() }
        t.resume()
        timer = t

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didMountNotification, object: nil)
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didUnmountNotification, object: nil)
    }

    @objc private func volumesChanged() {
        queue.async { [weak self] in self?.refreshAll() }
    }

    /// Instant and main-thread-safe. Assumes "available" until the first probe
    /// finishes, so a rule isn't briefly shown as broken at launch.
    func cached(source: String, destination: String) -> VolumeUtil.Availability {
        lock.lock(); defer { lock.unlock() }
        return cache[Self.key(source, destination)] ?? VolumeUtil.Availability(ok: true, reason: nil)
    }

    /// Authoritative check off the main thread; `completion` runs on the main queue.
    func verify(source: String, destination: String,
                completion: @escaping (VolumeUtil.Availability) -> Void) {
        queue.async { [weak self] in
            let result = VolumeUtil.availability(source: source, destination: destination)
            if let self {
                self.lock.lock()
                self.cache[Self.key(source, destination)] = result
                self.lock.unlock()
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Runs on `queue`.
    private func refreshAll() {
        let rules = DispatchQueue.main.sync { Store.shared.config.rules }
        var next: [String: VolumeUtil.Availability] = [:]
        for rule in rules where !(rule.source.isEmpty && rule.destination.isEmpty) {
            next[Self.key(rule.source, rule.destination)] =
                VolumeUtil.availability(source: rule.source, destination: rule.destination)
        }
        lock.lock(); cache = next; lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .dsConfigChanged, object: nil)
        }
    }
}
