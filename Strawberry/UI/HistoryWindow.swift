import AppKit
import SwiftUI
import Combine

private final class HistoryModel: ObservableObject {
    @Published var records: [SyncRecord] = Store.shared.history
    @Published var filter: UUID? = nil

    private var token: NSObjectProtocol?

    init() {
        token = NotificationCenter.default.addObserver(
            forName: .dsHistoryChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.records = Store.shared.history
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    var visible: [SyncRecord] {
        guard let filter else { return records }
        return records.filter { $0.ruleID == filter }
    }
}

struct HistoryView: View {
    @StateObject private var model = HistoryModel()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Rule", selection: $model.filter) {
                    Text("All rules").tag(UUID?.none)
                    ForEach(Store.shared.config.rules) { rule in
                        Text(rule.name).tag(UUID?.some(rule.id))
                    }
                }
                .frame(maxWidth: 260)
                Spacer()
                Button("Open Logs Folder") { NSWorkspace.shared.open(Store.shared.logsDir) }
                Button("Clear History") { Store.shared.clearHistory() }
                    .disabled(model.records.isEmpty)
            }
            .padding(10)

            Divider()

            if model.visible.isEmpty {
                VStack {
                    Spacer()
                    Text("No syncs recorded yet.").foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.visible) { record in
                    row(record)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    @ViewBuilder
    private func row(_ record: SyncRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(record.status.emoji)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.ruleName).fontWeight(.semibold)
                    if record.dryRun {
                        Text("DRY RUN")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.25))
                            .cornerRadius(3)
                    }
                    Spacer()
                    Text(Self.dateFormatter.string(from: record.startedAt))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(record.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Text("Took \(formatDuration(record.duration)) · exit \(record.exitCode)")
                        .font(.caption2).foregroundStyle(.tertiary)
                    if record.logFileName != nil {
                        Button("Show log") { openLog(record) }
                            .buttonStyle(.link).font(.caption2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func openLog(_ record: SyncRecord) {
        guard let name = record.logFileName else { return }
        NSWorkspace.shared.open(Store.shared.logsDir.appendingPathComponent(name))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }
}
