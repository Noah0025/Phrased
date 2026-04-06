import SwiftUI
import AppKit
import Carbon

// MARK: - SwiftUI wrapper

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt16
    @Binding var modifiers: [String]

    /// If true, a key press without a modifier is ignored (used for global hotkey).
    var requiresModifier: Bool = true
    /// If true, releasing all modifiers with no key records a modifier-only shortcut
    /// (only meaningful when requiresModifier == true). For in-app shortcuts use false.
    var allowModifierOnly: Bool = true
    /// Whether to append " ×2" in the display label (global double-tap hotkey).
    var showDoubleTap: Bool = true

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.requiresModifier  = requiresModifier
        view.allowModifierOnly = allowModifierOnly
        view.showDoubleTap     = showDoubleTap
        view.onRecorded = { newKeyCode, newModifiers in
            keyCode = newKeyCode
            modifiers = newModifiers
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.currentKeyCode  = keyCode
        nsView.currentModifiers = modifiers
        nsView.requiresModifier  = requiresModifier
        nsView.allowModifierOnly = allowModifierOnly
        nsView.showDoubleTap     = showDoubleTap
        nsView.needsDisplay = true
    }
}

// MARK: - NSView

class ShortcutRecorderNSView: NSView {
    /// UInt16.max is the sentinel for "modifier-only" (no key component).
    static let modifierOnlySentinel: UInt16 = UInt16.max

    var currentKeyCode: UInt16 = UInt16.max
    var currentModifiers: [String] = []
    var onRecorded: ((UInt16, [String]) -> Void)?

    var requiresModifier: Bool  = true
    var allowModifierOnly: Bool = true
    var showDoubleTap: Bool     = true

    private(set) var isRecording = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var mouseMonitor: Any?
    private var pendingModifiers: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else { return }
        window?.makeFirstResponder(self)
        startRecording()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { needsDisplay = true }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    // MARK: - Recording lifecycle

    private func startRecording() {
        isRecording = true
        pendingModifiers = []
        needsDisplay = true
        attachMonitors()
    }

    private func stopRecording() {
        isRecording = false
        pendingModifiers = []
        detachMonitors()
        needsDisplay = true
    }

    private func attachMonitors() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleRecordEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleRecordEvent(event)
            return nil // consume all key events while recording
        }
        // Exit recording when user clicks outside this view
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)
            if !self.bounds.contains(locationInView) {
                self.window?.makeFirstResponder(nil)
            }
            return event
        }
    }

    private func detachMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = mouseMonitor  { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    private func handleRecordEvent(_ event: NSEvent) {
        guard isRecording else { return }

        if event.type == .keyDown {
            // Escape cancels recording and clears the shortcut (= disabled)
            if event.keyCode == 53 {
                commit(keyCode: UInt16.max, modifiers: [])
                return
            }
            let mods = modifierStrings(from: event.modifierFlags)
            if requiresModifier && mods.isEmpty { return } // global needs at least one modifier
            commit(keyCode: event.keyCode, modifiers: mods)

        } else if event.type == .flagsChanged {
            guard allowModifierOnly else { return } // in-app shortcuts don't use modifier-only
            let relevant = event.modifierFlags.intersection([.shift, .control, .option, .command])
            if !relevant.isEmpty {
                pendingModifiers = relevant
            } else if !pendingModifiers.isEmpty {
                // All modifiers released — record as modifier-only shortcut
                let mods = modifierStrings(from: pendingModifiers)
                commit(keyCode: Self.modifierOnlySentinel, modifiers: mods)
            }
        }
    }

    private func commit(keyCode: UInt16, modifiers: [String]) {
        currentKeyCode = keyCode
        currentModifiers = modifiers
        onRecorded?(keyCode, modifiers)
        window?.makeFirstResponder(nil) // triggers resignFirstResponder → stopRecording
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius: CGFloat = 6
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        NSColor.controlBackgroundColor.setFill()
        path.fill()

        path.lineWidth = 1
        NSColor.separatorColor.setStroke()
        path.stroke()

        let hasShortcut = currentKeyCode != UInt16.max || !currentModifiers.isEmpty

        let label: String
        let color: NSColor
        if isRecording {
            label = "录制中…"
            color = NSColor.secondaryLabelColor
        } else if !hasShortcut {
            label = "点击设置"
            color = NSColor.placeholderTextColor
        } else {
            label = ShortcutRecorderNSView.displayString(
                keyCode: currentKeyCode,
                modifiers: currentModifiers,
                showDoubleTap: showDoubleTap
            )
            color = NSColor.labelColor
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: (bounds.width - sz.width) / 2,
                             y: (bounds.height - sz.height) / 2))
    }

    // MARK: - Helpers

    private func modifierStrings(from flags: NSEvent.ModifierFlags) -> [String] {
        var result: [String] = []
        if flags.contains(.control) { result.append("control") }
        if flags.contains(.option)  { result.append("option") }
        if flags.contains(.command) { result.append("command") }
        if flags.contains(.shift)   { result.append("shift") }
        return result
    }

    static func displayString(keyCode: UInt16, modifiers: [String], showDoubleTap: Bool = true) -> String {
        var mods = ""
        if modifiers.contains("control") { mods += "⌃" }
        if modifiers.contains("option")  { mods += "⌥" }
        if modifiers.contains("command") { mods += "⌘" }
        if modifiers.contains("shift")   { mods += "⇧" }

        let hasKey = keyCode != UInt16.max
        if showDoubleTap {
            // Global hotkey: "⌃ ×2" (modifier-only) or "⌘ + A ×2" (modifier+key)
            let keyPart = hasKey ? " + \(keyLabel(keyCode))" : ""
            return mods + keyPart + " ×2"
        } else {
            // In-app shortcut: "⌘ + A" or just "A" (bare key)
            if hasKey {
                let key = keyLabel(keyCode)
                return mods.isEmpty ? key : "\(mods) + \(key)"
            }
            return mods
        }
    }

    private static func keyLabel(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "⎋"
        default:
            // Attempt layout-aware name via UCKeyTranslate
            guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let dataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                return "(\(keyCode))"
            }
            let data = unsafeBitCast(dataRef, to: CFData.self)
            let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay),
                           0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit),
                           &dead, 4, &len, &chars)
            guard len > 0 else { return "(\(keyCode))" }
            return String(chars.prefix(len).map { Character(UnicodeScalar($0)!) }).uppercased()
        }
    }
}
