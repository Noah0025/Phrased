import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem!

    init(appDelegate: NSObject) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusBarController.makeMenuBarIcon()

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

    // MARK: - Menubar icon: "P✦" template image

    private static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // P — bold geometric, left-aligned
            let pAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
            let pStr = NSAttributedString(string: "P", attributes: pAttrs)
            let pSize = pStr.size()
            pStr.draw(at: NSPoint(x: 1, y: (rect.height - pSize.height) / 2))

            // ✦ — small four-pointed star, bottom-right of P (matching app icon)
            let starAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 6, weight: .regular),
                .foregroundColor: NSColor.black
            ]
            let starStr = NSAttributedString(string: "✦", attributes: starAttrs)
            starStr.draw(at: NSPoint(x: pSize.width + 1, y: 1))
            return true
        }
        image.isTemplate = true  // macOS auto-adapts to light/dark mode
        image.accessibilityDescription = "Phrased"
        return image
    }
}
