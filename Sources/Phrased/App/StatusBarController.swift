import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem!

    init(appDelegate: NSObject, settings: PhrasedSettings) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusBarController.makeMenuBarIcon()

        let menu = NSMenu()
        let openTitle = NSLocalizedString("app.menu.open", comment: "")
        let openItem = NSMenuItem(title: openTitle,
                                  action: #selector(AppDelegate.menuOpen),
                                  keyEquivalent: "")
        if settings.hotkeyKeyCode == HotkeyManager.modifierOnlySentinel {
            // Modifier-only double-tap: use modifierMask for the prefix symbol(s),
            // and set keyEquivalent to the last modifier's Unicode symbol as the "key" char.
            // e.g. double-tap ⌃ → mask=.control + keyEquivalent="⌃" → renders as ⌃⌃
            openItem.keyEquivalentModifierMask = settings.hotkeyNSModifiers
            openItem.keyEquivalent = StatusBarController.lastModifierSymbol(settings.hotkeyModifiers)
        } else {
            openItem.keyEquivalent = StatusBarController.keyChar(settings.hotkeyKeyCode)
            openItem.keyEquivalentModifierMask = settings.hotkeyNSModifiers
        }
        openItem.target = appDelegate
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: NSLocalizedString("app.menu.history", comment: ""),
                     action: #selector(AppDelegate.menuHistory),
                     keyEquivalent: "").target = appDelegate
        let settingsItem = NSMenuItem(title: NSLocalizedString("app.menu.settings", comment: ""),
                                      action: #selector(AppDelegate.menuSettings),
                                      keyEquivalent: ",")
        settingsItem.target = appDelegate
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: NSLocalizedString("app.menu.quit", comment: ""),
                                  action: #selector(AppDelegate.menuQuit),
                                  keyEquivalent: "q")
        quitItem.target = appDelegate
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    // MARK: - Hotkey display helpers

    private static func modifierSymbols(_ mods: [String]) -> String {
        var s = ""
        if mods.contains("control") { s += "⌃" }
        if mods.contains("option")  { s += "⌥" }
        if mods.contains("shift")   { s += "⇧" }
        if mods.contains("command") { s += "⌘" }
        return s
    }

    /// Returns the Unicode symbol of the "last" (highest precedence) modifier,
    /// used as the keyEquivalent character for double-tap display.
    private static func lastModifierSymbol(_ mods: [String]) -> String {
        if mods.contains("command") { return "⌘" }
        if mods.contains("shift")   { return "⇧" }
        if mods.contains("option")  { return "⌥" }
        if mods.contains("control") { return "⌃" }
        return ""
    }

    private static func keyChar(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"a", 1:"s", 2:"d", 3:"f", 4:"h", 5:"g", 6:"z", 7:"x",
            8:"c", 9:"v", 11:"b", 12:"q", 13:"w", 14:"e", 15:"r",
            16:"y", 17:"t", 18:"1", 19:"2", 20:"3", 21:"4", 22:"6",
            23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0",
            30:"]", 31:"o", 32:"u", 33:"[", 34:"i", 35:"p",
            37:"l", 38:"j", 39:"'", 40:"k", 41:";", 42:"\\",
            43:",", 44:"/", 45:"n", 46:"m", 47:".", 49:" "
        ]
        return map[keyCode] ?? ""
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
