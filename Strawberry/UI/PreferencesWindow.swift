import AppKit
import SwiftUI

private final class PreferencesModel: ObservableObject {
    @Published var launchAtLogin = LoginItem.isEnabled
    @Published var showFailureDialog = Store.shared.config.showFailureDialog
    @Published var mediaEventGapHours = Store.shared.config.mediaEventGapHours
    @Published var rsyncPath = Store.shared.config.rsyncPath

    func setLaunchAtLogin(_ on: Bool) {
        LoginItem.set(on)
        launchAtLogin = LoginItem.isEnabled
        Store.shared.mutateConfig { $0.launchAtLogin = self.launchAtLogin }
    }

    func setShowFailureDialog(_ on: Bool) {
        showFailureDialog = on
        Store.shared.mutateConfig { $0.showFailureDialog = on }
    }

    func setGap(_ hours: Double) {
        mediaEventGapHours = hours
        Store.shared.mutateConfig { $0.mediaEventGapHours = hours }
    }

    func chooseRsync() {
        let start = (rsyncPath as NSString).deletingLastPathComponent
        guard let path = PanelHelper.chooseFile(
            title: "Select the rsync executable (rsync 3.x recommended)",
            start: start.isEmpty ? "/opt/homebrew/bin" : start) else { return }
        RsyncCaps.invalidate()
        rsyncPath = path
        Store.shared.mutateConfig { $0.rsyncPath = path }
    }
}

struct PreferencesView: View {
    @StateObject private var model = PreferencesModel()

    private let gapOptions: [Double] = [0, 4, 8, 12, 24]

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                Toggle("Show a dialog when a sync fails", isOn: Binding(
                    get: { model.showFailureDialog }, set: model.setShowFailureDialog))
            }

            Section("Media Organization") {
                Picker("Media event gap", selection: Binding(
                    get: { model.mediaEventGapHours }, set: model.setGap)) {
                    ForEach(gapOptions, id: \.self) { hours in
                        Text(hours == 0 ? "Daily (split at midnight)" : "\(Int(hours)) hours").tag(hours)
                    }
                }
                Text("A shoot that runs past midnight stays in one folder until the gap between consecutive shots exceeds this.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("rsync") {
                HStack {
                    Text(model.rsyncPath)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") { model.chooseRsync() }
                }
                Text("rsync \(RsyncCaps.get(model.rsyncPath).version)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button("Reveal Data Folder in Finder") {
                    NSWorkspace.shared.open(Store.shared.baseDir)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 440)
    }
}
