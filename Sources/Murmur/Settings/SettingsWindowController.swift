import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let hosting: NSHostingController<SettingsView>

    init(settings: MurmurSettings, onSave: @escaping (MurmurSettings) -> Void) {
        let view = SettingsView(settings: settings, onSave: onSave)
        let hosting = NSHostingController(rootView: view)
        self.hosting = hosting
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
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        // Note: hosting.rootView is a value copy, so @State vars like hasUnsavedChanges
        // reflect initial values here. The real flush happens in SettingsView.onDisappear.
        // This call is a best-effort fallback for edge cases where onDisappear may not fire.
        hosting.rootView.flushPendingSave()
    }
}
