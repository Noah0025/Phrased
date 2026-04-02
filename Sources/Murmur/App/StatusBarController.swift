import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem
    private let onOpen: () -> Void

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Murmur")
            button.action = #selector(handleClick)
            button.target = self
        }
    }

    @objc private func handleClick() {
        onOpen()
    }
}
