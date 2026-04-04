import AppKit
import SwiftUI

class HistoryWindowController: NSWindowController {
    init(store: HistoryStore) {
        let hosting = NSHostingController(rootView: HistoryView(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Murmur 历史记录"
        window.contentViewController = hosting
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}

struct HistoryView: View {
    let store: HistoryStore
    @State private var entries: [HistoryEntry] = []

    var body: some View {
        List(entries.reversed()) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.templateName)
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    if let app = entry.appName {
                        Text(app).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(entry.createdAt, style: .relative)
                        .font(.caption2).foregroundColor(.secondary)
                }
                Text(entry.input)
                    .font(.system(size: 13)).foregroundColor(.secondary)
                Text(entry.output)
                    .font(.system(size: 13)).textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
        .onAppear { entries = (try? store.load()) ?? [] }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("清空历史") { try? store.clear(); entries = [] }
            }
        }
    }
}
