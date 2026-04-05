import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SelectableText
// NSTextView-backed: non-editable, selectable, Cmd+C works correctly.
// Subclass overrides acceptsFirstResponder so clicking makes it first responder
// (non-editable NSTextView returns false by default, blocking keyboard shortcuts).
private class _SelectableTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { setSelectedRange(NSRange(location: 0, length: 0)) }
        return result
    }

    /// SwiftUI's hosting view can consume command-key equivalents before AppKit
    /// routes them through the normal responder path for embedded NSTextView.
    /// Handle standard selection/copy shortcuts here so selected text still
    /// responds to Cmd+C/Cmd+A inside the history window.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only handle when this view is the active first responder.
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let onlyCmd = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        guard onlyCmd else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "a":
            selectAll(nil)
            return true
        case "c":
            guard selectedRange().length > 0 else { return super.performKeyEquivalent(with: event) }
            copy(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private struct SelectableText: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 13
    var color: NSColor = .labelColor

    func makeNSView(context: Context) -> _SelectableTextView {
        let tv = _SelectableTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        return tv
    }

    func updateNSView(_ tv: _SelectableTextView, context: Context) {
        if tv.string != text { tv.string = text }
        tv.font = .systemFont(ofSize: fontSize)
        tv.textColor = color
    }
}

// MARK: - HistoryWindowController

class HistoryWindowController: NSWindowController {
    init(store: HistoryStore, groupMode: HistoryGroupMode = .date) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: screen.width / 2, height: screen.height / 2)
        let origin = NSPoint(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2
        )
        let hosting = NSHostingController(rootView: HistoryView(store: store, initialGroupMode: groupMode))
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Murmur 历史记录"
        window.minSize = NSSize(width: 500, height: 360)
        window.contentViewController = hosting
        window.setContentSize(size)
        window.setFrameOrigin(origin)
        window.isRestorable = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - TimeRange

private enum TimeRange: String, CaseIterable, Identifiable {
    case today    = "今天"
    case week     = "最近7天"
    case month    = "最近30天"
    case all      = "全部"
    var id: String { rawValue }
}

// MARK: - HistoryView

struct HistoryView: View {
    let store: HistoryStore
    let initialGroupMode: HistoryGroupMode
    @State private var entries: [HistoryEntry] = []
    @State private var selection: Set<UUID> = []
    @State private var searchText: String = ""
    @State private var timeRange: TimeRange = .all
    @State private var filterTemplate: String = "全部"
    @State private var filterApp: String = "全部"
    @State private var showFilters: Bool = false
    @State private var groupMode: HistoryGroupMode = .date
    @State private var collapsed: Set<String> = []

    init(store: HistoryStore, initialGroupMode: HistoryGroupMode = .date) {
        self.store = store
        self.initialGroupMode = initialGroupMode
        _groupMode = State(initialValue: initialGroupMode)
    }

    // MARK: Available filter options (derived from entries)

    private var availableTemplates: [String] {
        let names = Set(entries.map(\.templateName)).sorted()
        return ["全部"] + names
    }

    private var availableApps: [String] {
        let apps = Set(entries.compactMap(\.appName)).sorted()
        let hasOther = entries.contains { $0.appName == nil }
        return ["全部"] + apps + (hasOther ? ["其他"] : [])
    }

    private var filtersActive: Bool {
        timeRange != .all || filterTemplate != "全部" || filterApp != "全部"
    }

    // MARK: Filtering

    private var filtered: [HistoryEntry] {
        let now = Date()
        let cal = Calendar.current
        return entries.filter { e in
            switch timeRange {
            case .today:  guard cal.isDateInToday(e.createdAt) else { return false }
            case .week:   guard e.createdAt >= now.addingTimeInterval(-7 * 86400) else { return false }
            case .month:  guard e.createdAt >= now.addingTimeInterval(-30 * 86400) else { return false }
            case .all:    break
            }
            if filterTemplate != "全部" {
                guard e.templateName == filterTemplate else { return false }
            }
            if filterApp != "全部" {
                if filterApp == "其他" {
                    guard e.appName == nil else { return false }
                } else {
                    guard e.appName == filterApp else { return false }
                }
            }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                guard e.input.lowercased().contains(q) || e.output.lowercased().contains(q)
                    || e.templateName.lowercased().contains(q) else { return false }
            }
            return true
        }
    }

    /// Generic groups: (key label, sort key for ordering groups, entries sorted newest first)
    private var groupedEntries: [(label: String, sortKey: String, entries: [HistoryEntry])] {
        let cal = Calendar.current
        var dict: [String: [HistoryEntry]] = [:]
        for e in filtered {
            let key: String
            switch groupMode {
            case .date:
                let day = cal.startOfDay(for: e.createdAt)
                key = day.formatted(.iso8601.year().month().day())
            case .template:
                key = e.templateName
            case .app:
                key = e.appName ?? "其他"
            }
            dict[key, default: []].append(e)
        }
        return dict.keys.sorted(by: >).map { key in
            let sorted = dict[key]!.sorted { $0.createdAt > $1.createdAt }
            let label: String
            switch groupMode {
            case .date:
                if let date = try? Date(key, strategy: .iso8601.year().month().day()) {
                    label = dateGroupLabel(date)
                } else { label = key }
            case .template, .app:
                label = key
            }
            return (label: label, sortKey: key, entries: sorted)
        }
    }

    private func dateGroupLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: search + filter toggle
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("搜索…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showFilters.toggle() }
                    } label: {
                        Image(systemName: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(filtersActive ? .accentColor : .secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("筛选")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                // Secondary filter row
                if showFilters {
                    Divider()
                    HStack(spacing: 12) {
                        filterPicker(title: "来源", selection: $filterApp, options: availableApps, label: { $0 })
                        Divider().frame(height: 16)
                        filterPicker(title: "风格", selection: $filterTemplate, options: availableTemplates, label: { $0 })
                        Divider().frame(height: 16)
                        filterPicker(title: "时间", selection: $timeRange, options: TimeRange.allCases, label: \.rawValue)
                        if filtersActive {
                            Divider().frame(height: 16)
                            Button("重置") {
                                timeRange = .all
                                filterTemplate = "全部"
                                filterApp = "全部"
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            .clipped()

            Divider()

            // Record list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    if groupedEntries.isEmpty {
                        Text(entries.isEmpty ? "暂无记录" : "无匹配结果")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ForEach(groupedEntries, id: \.sortKey) { group in
                            Section {
                                if !collapsed.contains(group.sortKey) {
                                    ForEach(group.entries) { entry in
                                        rowView(entry)
                                            .contextMenu { rowMenu(entry) }
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            } header: {
                                groupHeader(label: group.label, key: group.sortKey, count: group.entries.count)
                            }
                        }
                    }
                }
            }

            Divider()

            // Bottom toolbar
            HStack(spacing: 10) {
                Button(role: .destructive) { deleteSelected() } label: {
                    Text(selection.isEmpty ? "清空全部" : "删除所选")
                }
                .disabled(entries.isEmpty)

                Spacer()

                Button {
                    let toExport: [HistoryEntry]
                    if !selection.isEmpty {
                        toExport = filtered.filter { selection.contains($0.id) }
                    } else if searchText.isEmpty && timeRange == .all {
                        toExport = Array(entries.reversed())
                    } else {
                        toExport = filtered.sorted { $0.createdAt > $1.createdAt }
                    }
                    exportEntries(toExport)
                } label: {
                    Text(selection.isEmpty ? "导出全部" : "导出所选")
                }
                .disabled(entries.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear { reload() }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: Filter picker helper

    @ViewBuilder
    private func filterPicker<T: Hashable>(
        title: String,
        selection: Binding<T>,
        options: [T],
        label: @escaping (T) -> String
    ) -> some View {
        HStack(spacing: 3) {
            Text(title + "：")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { opt in
                    Text(label(opt)).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: Group header

    private func groupHeader(label: String, key: String, count: Int) -> some View {
        Button {
            if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: collapsed.contains(key) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("(\(count))")
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondary.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        }
        .buttonStyle(.plain)
    }

    // MARK: Row

    private func rowView(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: Binding(
                get: { selection.contains(entry.id) },
                set: { if $0 { selection.insert(entry.id) } else { selection.remove(entry.id) } }
            )) { EmptyView() }
            .toggleStyle(.checkbox)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                // Meta row
                HStack(spacing: 6) {
                    Text(entry.templateName)
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    if let app = entry.appName {
                        Text(app).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundColor(.secondary)
                }
                // Input
                SelectableText(text: entry.input, color: .secondaryLabelColor)
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                // Output
                SelectableText(text: entry.output)
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Context menu

    @ViewBuilder
    private func rowMenu(_ entry: HistoryEntry) -> some View {
        Button("复制输入") { copy(entry.input) }
        Button("复制输出") { copy(entry.output) }
        Divider()
        Button("删除", role: .destructive) {
            try? store.delete(ids: [entry.id])
            selection.remove(entry.id)
            reload()
        }
    }

    // MARK: Actions

    private func deleteSelected() {
        let ids = selection.isEmpty ? Set(entries.map(\.id)) : selection
        if ids.count == entries.count {
            try? store.clear()
        } else {
            try? store.delete(ids: ids)
        }
        selection = []
        reload()
    }

    private func exportEntries(_ toExport: [HistoryEntry]) {
        let panel = NSSavePanel()
        panel.title = "导出历史记录"
        panel.nameFieldStringValue = "Murmur 历史记录"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let body = toExport.map { e in
                let meta = "[\(e.createdAt.formatted(date: .abbreviated, time: .shortened))] 风格：\(e.templateName)"
                    + (e.appName.map { " | \($0)" } ?? "")
                return "\(meta)\n输入：\(e.input)\n输出：\(e.output)"
            }.joined(separator: "\n\n---\n\n")
            let header = "Murmur 历史记录  导出于 \(Date().formatted())\n\n---\n\n"
            try? (header + body).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func reload() {
        entries = (try? store.load()) ?? []
    }
}
