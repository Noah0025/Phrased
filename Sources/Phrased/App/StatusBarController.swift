import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem!

    init(appDelegate: NSObject) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Phrased")

        let menu = NSMenu()
        menu.addItem(withTitle: NSLocalizedString("app.menu.open", comment: ""),
                     action: #selector(AppDelegate.menuOpen),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(.separator())
        menu.addItem(withTitle: NSLocalizedString("app.menu.history", comment: ""),
                     action: #selector(AppDelegate.menuHistory),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(withTitle: NSLocalizedString("app.menu.settings", comment: ""),
                     action: #selector(AppDelegate.menuSettings),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(.separator())
        menu.addItem(withTitle: NSLocalizedString("app.menu.quit", comment: ""),
                     action: #selector(AppDelegate.menuQuit),
                     keyEquivalent: "").target = appDelegate
        statusItem.menu = menu
    }
}
