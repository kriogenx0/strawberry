import AppKit
import SwiftUI

/// The single "Organize Media" entry point: a tabbed dialog to organize either a
/// mounted volume or an arbitrary folder.
struct OrganizeMediaView: View {
    let onClose: () -> Void

    @State private var volumes = MediaOrganizer.volumesList()
        .filter { MediaOrganizer.canRunOnVolume(volume: $0) }
    /// nil == "All media volumes".
    @State private var selectedVolume: URL?
    @State private var folder: URL?

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                volumeTab.tabItem { Label("Volume", systemImage: "sdcard") }
                folderTab.tabItem { Label("Folder", systemImage: "folder") }
            }
            .padding([.horizontal, .top], 12)

            Divider()

            HStack {
                Spacer()
                Button("Close", action: onClose).keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 320)
    }

    // MARK: Volume

    private var volumeTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sort a mounted card's DCIM folder into Year / Month-Day / event folders, in place.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if volumes.isEmpty {
                Spacer()
                Text("No mounted volume has a DCIM folder.")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Picker("", selection: $selectedVolume) {
                    Text("All media volumes").tag(URL?.none)
                    ForEach(volumes, id: \.self) { volume in
                        Text(volume.lastPathComponent).tag(URL?.some(volume))
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                Spacer()
            }

            HStack {
                Spacer()
                Button("Organize") { organizeVolumeSelection() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(volumes.isEmpty)
            }
        }
        .padding(16)
    }

    private func organizeVolumeSelection() {
        if let volume = selectedVolume {
            perform {
                MediaOrganizer.runOnVolume(volume: volume)
                MediaOrganizer.showInFinder(url: volume)
            }
        } else {
            perform { MediaOrganizer.runOnAllVolumes() }
        }
    }

    // MARK: Folder

    private var folderTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Organize any folder of camera-style subfolders, in place.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(folder?.path ?? "No folder chosen")
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(folder == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Choose…") { chooseFolder() }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)

            Spacer()

            HStack {
                Spacer()
                Button("Organize") {
                    guard let folder else { return }
                    perform {
                        MediaOrganizer.runOnDirectory(directoryUrl: folder)
                        MediaOrganizer.showInFinder(url: folder)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folder == nil)
            }
        }
        .padding(16)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        PanelHelper.activateApp()
        if panel.runModal() == .OK { folder = panel.url }
    }

    // MARK: -

    /// Close the dialog first, then run the (synchronous, alert-popping) organize
    /// on the next runloop tick so the window is gone before it blocks.
    private func perform(_ action: @escaping () -> Void) {
        onClose()
        DispatchQueue.main.async(execute: action)
    }
}
