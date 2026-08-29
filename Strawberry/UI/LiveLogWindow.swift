import SwiftUI
import Combine

final class LiveLogModel: ObservableObject {
    @Published private(set) var text = Scheduler.shared.runningLogText
    @Published private(set) var ruleName: String = ""
    @Published private(set) var isRunning = false

    private var token: NSObjectProtocol?

    init() {
        refresh()
        token = NotificationCenter.default.addObserver(
            forName: .dsRunStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    private func refresh() {
        let scheduler = Scheduler.shared
        isRunning = scheduler.runningRuleID != nil
        if isRunning {
            text = scheduler.runningLogText
            if let id = scheduler.runningRuleID {
                ruleName = Store.shared.config.rules.first(where: { $0.id == id })?.name ?? "Sync"
            }
        } else if !scheduler.runningLogText.isEmpty {
            // a run finished this session — keep its in-memory tail
            text = scheduler.runningLogText
        } else {
            // fall back to the last completed run's log file on disk
            loadLastRunLog()
        }
    }

    private func loadLastRunLog() {
        guard let record = Store.shared.history.first, let name = record.logFileName else {
            text = ""
            ruleName = ""
            return
        }
        ruleName = record.ruleName
        let url = Store.shared.logsDir.appendingPathComponent(name)
        DispatchQueue.global(qos: .utility).async {
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? "(log file could not be read: \(name))"
            let tail = String(contents.suffix(400_000))
            DispatchQueue.main.async { [weak self] in self?.text = tail }
        }
    }
}

struct LiveLogView: View {
    @StateObject private var model = LiveLogModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.isRunning ? "Live output — \(model.ruleName)" : "Most recent sync output")
                    .font(.headline)
                Spacer()
                if model.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Live").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    Text(model.text.isEmpty ? "Waiting for rsync output…" : model.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Color.clear.frame(height: 1).id("log-end")
                }
                .onAppear { proxy.scrollTo("log-end", anchor: .bottom) }
                .onChange(of: model.text) { _ in
                    proxy.scrollTo("log-end", anchor: .bottom)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 380)
    }
}
