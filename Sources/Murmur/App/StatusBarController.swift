import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem!

    init(appDelegate: NSObject) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Murmur")

        let menu = NSMenu()
        menu.addItem(withTitle: "打开 Murmur",
                     action: #selector(AppDelegate.menuOpen),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(.separator())
        menu.addItem(withTitle: "历史记录",
                     action: #selector(AppDelegate.menuHistory),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(withTitle: "设置…",
                     action: #selector(AppDelegate.menuSettings),
                     keyEquivalent: ",").target = appDelegate
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Murmur",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        statusItem.menu = menu
    }
}
