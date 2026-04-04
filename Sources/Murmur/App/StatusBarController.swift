import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem!
    private let onOpen: () -> Void
    private let onSettings: () -> Void
    private let onHistory: () -> Void

    init(
        onOpen: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onHistory: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onSettings = onSettings
        self.onHistory = onHistory
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Murmur")
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 Murmur",  action: #selector(doOpen),     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "历史记录",      action: #selector(doHistory),  keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…",         action: #selector(doSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Murmur",  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func doOpen()     { onOpen() }
    @objc private func doSettings() { onSettings() }
    @objc private func doHistory()  { onHistory() }
}
