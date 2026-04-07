import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let hosting: NSHostingController<SettingsView>
    private static var activeScreen: NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    init(settings: PhrasedSettings,
         onSave: @escaping (PhrasedSettings) -> Void,
         onOpenHistory: (() -> Void)? = nil,
         onExportHistory: (() -> Void)? = nil) {
        let view = SettingsView(settings: settings, onSave: onSave,
                                onOpenHistory: onOpenHistory, onExportHistory: onExportHistory)
        let hosting = NSHostingController(rootView: view)
        self.hosting = hosting
        let screen = Self.activeScreen.visibleFrame
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
        window.title = NSLocalizedString("app.window.settings.title", comment: "")
        window.minSize = NSSize(width: 500, height: 360)
        window.contentViewController = hosting
        window.setContentSize(size)
        window.setFrameOrigin(origin)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateSettings(_ settings: PhrasedSettings,
                        onSave: @escaping (PhrasedSettings) -> Void,
                        onOpenHistory: (() -> Void)?,
                        onExportHistory: (() -> Void)?) {
        hosting.rootView = SettingsView(
            settings: settings,
            onSave: onSave,
            onOpenHistory: onOpenHistory,
            onExportHistory: onExportHistory
        )
    }

    // Save is handled by SettingsView.onDisappear; windowWillClose on a value-type
    // rootView would operate on a stale copy, so we intentionally do nothing here.
}
