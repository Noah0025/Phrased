import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    init(settings: MurmurSettings, onSave: @escaping (MurmurSettings) -> Void) {
        let view = SettingsView(settings: settings, onSave: onSave)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Murmur 设置"
        window.contentViewController = hosting
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
