import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    init(settings: MurmurSettings, onSave: @escaping (MurmurSettings) -> Void) {
        let view = SettingsView(settings: settings, onSave: onSave)
        let hosting = NSHostingController(rootView: view)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: screen.width / 2, height: screen.height / 2)
        let origin = NSPoint(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2
        )
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Murmur 设置"
        window.minSize = NSSize(width: 500, height: 360)
        window.contentViewController = hosting
        window.setContentSize(size)
        window.setFrameOrigin(origin)
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
