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
    var font: NSFont = PhrasedFont.nsUI
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
        tv.font = font
        tv.textColor = color
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: _SelectableTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0,
              let container = nsView.textContainer,
              let layout = nsView.layoutManager else { return nil }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return CGSize(width: width, height: max(18, ceil(used.height)))
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
        window.title = NSLocalizedString("app.window.history.title", comment: "")
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
    case today = "today"
    case week = "week"
    case month = "month"
    case all = "all"
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .today:
            return LocalizedStringKey("history.time.today")
        case .week:
            return LocalizedStringKey("history.time.last_7_days")
        case .month:
            return LocalizedStringKey("history.time.last_30_days")
        case .all:
            return LocalizedStringKey("history.time.all")
        }
    }
}

// MARK: - HistoryView

struct HistoryView: View {
    let store: HistoryStore
    let initialGroupMode: HistoryGroupMode
    private let allFilterValue = NSLocalizedString("history.time.all", comment: "")
    private let otherFilterValue = NSLocalizedString("history.filter.other", comment: "")
    @State private var entries: [HistoryEntry] = []
    @State private var selection: Set<UUID> = []
    @State private var searchText: String = ""
    @State private var timeRange: TimeRange = .all
    @State private var filterTemplate: String
    @State private var filterApp: String
    @State private var showFilters: Bool = false
    @State private var groupMode: HistoryGroupMode = .date
    @State private var collapsed: Set<String> = []
    @State private var showCorruptionAlert = false

    init(store: HistoryStore, initialGroupMode: HistoryGroupMode = .date) {
        self.store = store
        self.initialGroupMode = initialGroupMode
        let allValue = NSLocalizedString("history.time.all", comment: "")
        _filterTemplate = State(initialValue: allValue)
        _filterApp = State(initialValue: allValue)
        _groupMode = State(initialValue: initialGroupMode)
    }

    // MARK: Available filter options (derived from entries)

    private var availableTemplates: [String] {
        let names = Set(entries.map(\.templateName)).sorted()
        return [allFilterValue] + names
    }

    private var availableApps: [String] {
        let apps = Set(entries.compactMap(\.appName)).sorted()
        let hasOther = entries.contains { $0.appName == nil }
        return [allFilterValue] + apps + (hasOther ? [otherFilterValue] : [])
    }

    private var filtersActive: Bool {
        timeRange != .all || filterTemplate != allFilterValue || filterApp != allFilterValue
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
            if filterTemplate != allFilterValue {
                guard e.templateName == filterTemplate else { return false }
            }
            if filterApp != allFilterValue {
                if filterApp == otherFilterValue {
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
                key = e.appName ?? otherFilterValue
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
        if cal.isDateInToday(date) {
            return NSLocalizedString("history.time.today", comment: "")
        }
        if cal.isDateInYesterday(date) {
            return NSLocalizedString("history.time.yesterday", comment: "")
        }
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
                        .font(PhrasedFont.secondary)
                    TextField(LocalizedStringKey("history.search.placeholder"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(PhrasedFont.ui)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(PhrasedFont.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "accessibility.clear_search"))
                    }
                    Button {
                        withAnimation(PhrasedAnimation.quick) { showFilters.toggle() }
                    } label: {
                        Image(systemName: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(filtersActive ? .accentColor : .secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("history.help.filter", comment: ""))
                    .accessibilityLabel(String(localized: "history.help.filter"))
                }
                .padding(.horizontal, PhrasedSpacing.lg)
                .padding(.vertical, PhrasedSpacing.sm)

                // Secondary filter row
                if showFilters {
                    Divider()
                    HStack(spacing: 12) {
                        filterPicker(titleKey: "history.filter.source", selection: $filterApp, options: availableApps, label: { $0 })
                        Divider().frame(height: 16)
                        filterPicker(titleKey: "history.filter.style", selection: $filterTemplate, options: availableTemplates, label: { $0 })
                        Divider().frame(height: 16)
                        timeRangePicker(titleKey: "history.filter.time", selection: $timeRange, options: TimeRange.allCases)
                        if filtersActive {
                            Divider().frame(height: 16)
                            Button(LocalizedStringKey("history.filter.reset")) {
                                timeRange = .all
                                filterTemplate = allFilterValue
                                filterApp = allFilterValue
                            }
                            .buttonStyle(.plain)
                            .font(PhrasedFont.caption)
                            .foregroundColor(.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, PhrasedSpacing.lg)
                    .padding(.vertical, PhrasedSpacing.sm)
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
                        Text(entries.isEmpty ? LocalizedStringKey("history.empty.no_records") : LocalizedStringKey("history.empty.no_matches"))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, PhrasedSpacing.xxl)
                    } else {
                        ForEach(groupedEntries, id: \.sortKey) { group in
                            Section {
                                if !collapsed.contains(group.sortKey) {
                                    ForEach(group.entries) { entry in
                                        rowView(entry)
                                            .contextMenu { rowMenu(entry) }
                                        Divider().padding(.leading, PhrasedSpacing.lg)
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
                    Text(selection.isEmpty ? LocalizedStringKey("history.button.clear_all") : LocalizedStringKey("history.button.delete_selected"))
                }
                .disabled(entries.isEmpty)

                Spacer()

                Button {
                    let toExport: [HistoryEntry]
                    if !selection.isEmpty {
                        toExport = filtered.filter { selection.contains($0.id) }
                    } else if filtersActive || !searchText.isEmpty {
                        toExport = filtered.sorted { $0.createdAt > $1.createdAt }
                    } else {
                        toExport = Array(entries.reversed())
                    }
                    HistoryExporter.export(entries: toExport)
                } label: {
                    Text(selection.isEmpty ? LocalizedStringKey("history.button.export_all") : LocalizedStringKey("history.button.export_selected"))
                }
                .disabled(entries.isEmpty)
            }
            .padding(.horizontal, PhrasedSpacing.lg)
            .padding(.vertical, PhrasedSpacing.sm + 2)
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .historyStoreDidChange)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyStoreCorruptionRecovered)) { _ in
            showCorruptionAlert = true
        }
        .alert(
            Text("history.alert.corrupted.title"),
            isPresented: $showCorruptionAlert
        ) {
            Button("OK") { }
        } message: {
            Text("history.alert.corrupted.message")
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: Filter picker helper

    @ViewBuilder
    private func filterPicker<T: Hashable>(
        titleKey: LocalizedStringKey,
        selection: Binding<T>,
        options: [T],
        label: @escaping (T) -> String
    ) -> some View {
        HStack(spacing: 3) {
            Text(titleKey)
                .font(PhrasedFont.caption)
                .foregroundColor(.secondary)
            Text(":")
                .font(PhrasedFont.caption)
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

    @ViewBuilder
    private func timeRangePicker(
        titleKey: LocalizedStringKey,
        selection: Binding<TimeRange>,
        options: [TimeRange]
    ) -> some View {
        HStack(spacing: 3) {
            Text(titleKey)
                .font(PhrasedFont.caption)
                .foregroundColor(.secondary)
            Text(":")
                .font(PhrasedFont.caption)
                .foregroundColor(.secondary)
            Picker("", selection: selection) {
                ForEach(options) { opt in
                    Text(opt.label).tag(opt)
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
            HStack(spacing: PhrasedSpacing.sm) {
                Image(systemName: collapsed.contains(key) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(PhrasedFont.secondarySemibold)
                    .foregroundColor(.secondary)
                Text("(\(count))")
                    .font(PhrasedFont.caption)
                    .foregroundColor(Color.secondary.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, PhrasedSpacing.lg)
            .padding(.vertical, PhrasedSpacing.sm)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count)")
        .accessibilityValue(collapsed.contains(key) ? String(localized: "accessibility.collapsed") : String(localized: "accessibility.expanded"))
    }

    // MARK: Row

    private func rowView(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: PhrasedSpacing.sm + 2) {
            Toggle(isOn: Binding(
                get: { selection.contains(entry.id) },
                set: { if $0 { selection.insert(entry.id) } else { selection.remove(entry.id) } }
            )) { EmptyView() }
            .toggleStyle(.checkbox)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: PhrasedSpacing.xs) {
                // Meta row
                HStack(spacing: PhrasedSpacing.sm) {
                    Text(entry.templateName)
                        .font(PhrasedFont.caption).foregroundColor(.secondary)
                        .padding(.horizontal, PhrasedSpacing.sm).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(PhrasedOpacity.lightFill)))
                    if let app = entry.appName {
                        Text(app).font(PhrasedFont.caption).foregroundColor(.secondary)
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
        .padding(.horizontal, PhrasedSpacing.lg)
        .padding(.vertical, PhrasedSpacing.sm + 2)
    }

    // MARK: Context menu

    @ViewBuilder
    private func rowMenu(_ entry: HistoryEntry) -> some View {
        Button(LocalizedStringKey("history.menu.copy_input")) { copy(entry.input) }
        Button(LocalizedStringKey("history.menu.copy_output")) { copy(entry.output) }
        Divider()
        Button(LocalizedStringKey("settings.button.delete"), role: .destructive) {
            do {
                try store.delete(ids: [entry.id])
            } catch {
                NSAlert(error: error).runModal()
            }
            selection.remove(entry.id)
            reload()
        }
    }

    // MARK: Actions

    private func deleteSelected() {
        let ids = selection.isEmpty ? Set(entries.map(\.id)) : selection
        if ids.count == entries.count {
            do {
                try store.clear()
            } catch {
                NSAlert(error: error).runModal()
            }
        } else {
            do {
                try store.delete(ids: ids)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        selection = []
        reload()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func reload() {
        do { entries = try store.load() }
        catch {
            entries = []
            NSAlert(error: error).runModal()
        }
    }
}
