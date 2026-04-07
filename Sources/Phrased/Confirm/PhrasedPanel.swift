import SwiftUI
import AppKit

// MARK: - PhrasedPanel

/// NSPanel subclass that allows the panel to become the key window,
/// enabling ⌘V / ⌘A and other key equivalents to reach the text view.
class PhrasedPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var appShortcutHandler: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if appShortcutHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class FirstMouseHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = FirstMouseHostingView(rootView: rootView)
    }
}
