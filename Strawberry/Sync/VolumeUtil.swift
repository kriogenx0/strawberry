import Foundation
import Darwin
import AppKit

/// Helpers for deciding whether a rule's endpoints are actually present.
///
/// The important safety property: when an external drive is unplugged its
/// `/Volumes/<Name>` mount point usually disappears, but not always — sometimes a
/// stale empty folder is left on the boot disk. Writing a sync into that folder
/// would silently fill the startup disk. So for anything under `/Volumes/` we
/// require the path to sit on a *separately mounted* filesystem.
enum VolumeUtil {

    /// Mount point (`f_mntonname`) of the filesystem that contains `path`,
    /// walking up to the nearest ancestor that exists.
    static func mountPoint(for path: String) -> String? {
        var probe = (path as NSString).standardizingPath
        let fm = FileManager.default
        while !fm.fileExists(atPath: probe) {
            let parent = (probe as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == probe { return nil }
            probe = parent
        }
        var info = statfs()
        guard statfs(probe, &info) == 0 else { return nil }
        return withUnsafeBytes(of: &info.f_mntonname) { raw -> String in
            guard let base = raw.baseAddress else { return "/" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

    static func volumeName(for path: String) -> String {
        let mp = mountPoint(for: path) ?? "/"
        return mp == "/" ? "Macintosh HD" : (mp as NSString).lastPathComponent
    }

    struct Availability {
        var ok: Bool
        var reason: String?
    }

    /// For a path under `/Volumes/<Name>/…`, check that `<Name>` is an actual
    /// mounted filesystem and not a leftover empty folder on the boot disk.
    /// Returns `nil` if the path is not under `/Volumes/` (nothing to check), the
    /// volume name otherwise, and `ok == false` when it isn't mounted.
    static func mountedVolumeCheck(for path: String) -> (name: String, mounted: Bool)? {
        let std = (path as NSString).standardizingPath
        let comps = std.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard comps.first == "Volumes", comps.count >= 2 else { return nil }

        let root = "/Volumes/\(comps[1])"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            return (comps[1], false)
        }
        // A real mount reports itself as its own `f_mntonname`; a stale stub on
        // the boot disk reports `/`.
        return (comps[1], mountPoint(for: root) == root)
    }

    /// Is `path` a usable *source* directory right now? It must exist, be a
    /// directory, sit on a real mount (not a stale `/Volumes/…` stub), and
    /// contain at least one item — an empty source almost always means "the
    /// drive isn't mounted / isn't the one you think", and letting a Mirror run
    /// against it would wipe the destination.
    static func sourceAvailable(_ path: String) -> Availability {
        let std = (path as NSString).standardizingPath
        if std.isEmpty { return .init(ok: false, reason: "no folder set") }

        if let vol = mountedVolumeCheck(for: std), !vol.mounted {
            return .init(ok: false, reason: "drive “\(vol.name)” is not mounted")
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: std, isDirectory: &isDir), isDir.boolValue else {
            return .init(ok: false, reason: "folder not found")
        }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: std)) ?? []
        if entries.isEmpty {
            return .init(ok: false, reason: "source folder is empty")
        }
        return .init(ok: true, reason: nil)
    }

    /// Is `path` a usable *destination* right now? The leaf folder need not exist
    /// yet (rsync `--mkpath` creates it), but the drive must be mounted.
    static func destinationAvailable(_ path: String) -> Availability {
        let std = (path as NSString).standardizingPath
        if std.isEmpty { return .init(ok: false, reason: "no folder set") }

        if let vol = mountedVolumeCheck(for: std), !vol.mounted {
            return .init(ok: false, reason: "drive “\(vol.name)” is not mounted")
        }
        // The nearest existing ancestor must be a real directory.
        var probe = std
        while !FileManager.default.fileExists(atPath: probe) {
            let parent = (probe as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == probe {
                return .init(ok: false, reason: "path unreachable")
            }
            probe = parent
        }
        return .init(ok: true, reason: nil)
    }

    static func availability(source: String, destination: String) -> Availability {
        let s = sourceAvailable(source)
        guard s.ok else { return .init(ok: false, reason: "source: \(s.reason ?? "unavailable")") }
        let d = destinationAvailable(destination)
        guard d.ok else { return .init(ok: false, reason: "destination: \(d.reason ?? "unavailable")") }
        return .init(ok: true, reason: nil)
    }
}

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
