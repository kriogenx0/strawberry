import AppKit
import SwiftUI

struct RuleEditorView: View {
    @State private var name: String
    @State private var source: String
    @State private var destination: String
    @State private var interval: SyncInterval
    @State private var enabled: Bool

    @State private var mode: SyncMode
    /// The mode before the current pick — used to revert if a Move confirm is declined.
    @State private var lastConfirmedMode: SyncMode
    @State private var showMoveConfirm = false
    @State private var wholeFile: Bool
    @State private var preallocate: Bool
    @State private var inPlace: Bool
    @State private var stayOnFS: Bool
    @State private var preservePerms: Bool
    @State private var lowPriority: Bool
    @State private var speedLimitText: String
    @State private var excludesText: String
    @State private var extraArgsText: String

    private static func numString(_ d: Double) -> String {
        d <= 0 ? "" : (d == d.rounded() ? String(Int(d)) : String(d))
    }

    private let ruleID: UUID
    private let isNew: Bool
    private let onSave: (SyncRule) -> Void
    private let onCancel: () -> Void
    private let onDelete: (() -> Void)?

    init(rule: SyncRule,
         isNew: Bool,
         onSave: @escaping (SyncRule) -> Void,
         onCancel: @escaping () -> Void,
         onDelete: (() -> Void)?) {
        _name = State(initialValue: rule.name)
        _source = State(initialValue: rule.source)
        _destination = State(initialValue: rule.destination)
        _interval = State(initialValue: rule.interval)
        _enabled = State(initialValue: rule.enabled)
        _mode = State(initialValue: rule.options.mode)
        _lastConfirmedMode = State(initialValue: rule.options.mode)
        _wholeFile = State(initialValue: rule.options.wholeFile)
        _preallocate = State(initialValue: rule.options.preallocate)
        _inPlace = State(initialValue: rule.options.inPlace)
        _stayOnFS = State(initialValue: rule.options.stayOnSourceFilesystem)
        _preservePerms = State(initialValue: rule.options.preservePermissions)
        _lowPriority = State(initialValue: rule.options.lowPriority)
        _speedLimitText = State(initialValue: Self.numString(rule.options.bandwidthLimitMBps))
        _excludesText = State(initialValue: rule.options.excludes.joined(separator: "\n"))
        _extraArgsText = State(initialValue: rule.options.extraArgs.joined(separator: " "))
        ruleID = rule.id
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
    }

    private var preallocSupported: Bool {
        RsyncCaps.get(Store.shared.config.rsyncPath).prealloc
    }

    private var assembled: SyncRule {
        var options = RsyncOptions()
        options.mode = mode
        options.wholeFile = wholeFile
        options.preallocate = preallocate
        options.inPlace = inPlace
        options.stayOnSourceFilesystem = stayOnFS
        options.preservePermissions = preservePerms
        options.lowPriority = lowPriority
        options.bandwidthLimitMBps = max(0, Double(speedLimitText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")) ?? 0)
        options.excludes = excludesText
            .split(whereSeparator: { $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        options.extraArgs = extraArgsText
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty }

        var rule = SyncRule(name: name.trimmingCharacters(in: .whitespaces),
                            source: (source as NSString).standardizingPath,
                            destination: (destination as NSString).standardizingPath)
        rule.id = ruleID
        rule.interval = interval
        rule.enabled = enabled
        rule.options = options
        if let existing = Store.shared.config.rules.first(where: { $0.id == ruleID }) {
            rule.lastSuccessAt = existing.lastSuccessAt
            rule.lastRunAt = existing.lastRunAt
            rule.lastStatus = existing.lastStatus
        }
        return rule
    }

    private var validationError: String? {
        let s = (source as NSString).standardizingPath
        let d = (destination as NSString).standardizingPath
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the rule a name." }
        if s.isEmpty || d.isEmpty { return "Choose both a source and a destination folder." }
        if s == d { return "Source and destination must be different." }
        if (d + "/").hasPrefix(s + "/") { return "The destination is inside the source folder." }
        if (s + "/").hasPrefix(d + "/") { return "The source is inside the destination folder." }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    labeled("Name") {
                        TextField("e.g. Photos → Backup drive", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    pathRow("Source folder", $source)
                    pathRow("Destination folder", $destination)

                    labeled("Sync schedule") {
                        Picker("", selection: $interval) {
                            ForEach(SyncInterval.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260, alignment: .leading)
                    }

                    labeled("Sync mode") {
                        Picker("", selection: $mode) {
                            ForEach(SyncMode.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300, alignment: .leading)
                        .onChange(of: mode) { newMode in
                            if newMode == .move {
                                showMoveConfirm = true
                            } else {
                                lastConfirmedMode = newMode
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            effectLine("Source:", mode.sourceEffect, destructive: mode == .move)
                            effectLine("Destination:", mode.destinationEffect, destructive: mode == .mirror)
                        }

                        Text("Unchanged files (same size + timestamp) are always skipped; a changed file is always replaced.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .alert("Use Move mode?", isPresented: $showMoveConfirm) {
                        Button("Use Move Mode", role: .destructive) { lastConfirmedMode = .move }
                        Button("Cancel", role: .cancel) { mode = lastConfirmedMode }
                    } message: {
                        Text("After every sync, files that copied successfully are DELETED from the source folder. This is not reversible; skipped or failed files are left in place.")
                    }

                    Toggle("Rule enabled", isOn: $enabled)

                    Divider()
                    Text("rsync tuning").font(.headline)
                    Text("Defaults are tuned for spinning-disk to spinning-disk copies.")
                        .font(.caption).foregroundStyle(.secondary)

                    Toggle("Copy whole files — skip the delta algorithm (recommended disk-to-disk)", isOn: $wholeFile)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Preallocate files — less fragmentation on HDDs", isOn: $preallocate)
                            .disabled(!preallocSupported)
                        if !preallocSupported {
                            Text("This rsync (\(RsyncCaps.get(Store.shared.config.rsyncPath).version)) was built without prealloc support — the flag will be skipped.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("In-place updates — less scratch space, but a killed sync leaves a half-written file", isOn: $inPlace)
                    Toggle("Stay on the source filesystem — don't descend into nested mounts", isOn: $stayOnFS)
                    Toggle("Preserve permissions (turn off for exFAT / FAT destinations)", isOn: $preservePerms)
                    Toggle("Run at low priority — yield disk & CPU to foreground apps", isOn: $lowPriority)

                    labeled("Speed limit") {
                        HStack(spacing: 6) {
                            TextField("0", text: $speedLimitText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 72)
                            Text("MB/s   (0 or blank = no limit; caps transfer throughput via rsync --bwlimit)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    labeled("Exclude patterns (one per line)") {
                        TextEditor(text: $excludesText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 96)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3)))
                    }
                    labeled("Extra rsync arguments") {
                        TextField("--bwlimit=50m  --timeout=600", text: $extraArgsText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    labeled("Command preview") {
                        Text(RsyncRunner.previewCommand(for: assembled, dryRun: false))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive, action: onDelete)
                }
                Spacer()
                if let error = validationError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Rule" : "Save") { onSave(assembled) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationError != nil)
            }
            .padding(12)
        }
        .frame(width: 580, height: 660)
    }

    @ViewBuilder
    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            content()
        }
    }

    private func effectLine(_ label: String, _ text: String, destructive: Bool) -> some View {
        (Text(label).fontWeight(.semibold) + Text(" \(text)"))
            .font(.callout)
            .foregroundStyle(destructive ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pathRow(_ title: String, _ binding: Binding<String>) -> some View {
        labeled(title) {
            HStack {
                TextField("/Volumes/…", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Choose…") {
                    if let picked = PanelHelper.chooseDirectory(
                        title: title,
                        start: binding.wrappedValue.isEmpty ? nil : binding.wrappedValue) {
                        binding.wrappedValue = picked
                    }
                }
            }
        }
    }
}
