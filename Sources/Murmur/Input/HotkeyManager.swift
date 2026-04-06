import AppKit

/// Triggers `onActivate` when the registered shortcut is pressed twice within `doubleTapWindow` seconds.
///
/// - `keyCode == 0` means modifier-only (e.g. double-tap Ctrl).
/// - Otherwise the trigger is modifier+key pressed twice in quick succession.
class HotkeyManager {
    private(set) var keyCode: UInt16
    private(set) var modifierFlags: NSEvent.ModifierFlags

    private let doubleTapWindow: TimeInterval = 0.5
    private var onActivate: () -> Void
    private var monitors: [Any] = []

    /// Tracks the last time a matching press was detected.
    private var lastPressTime: Date = .distantPast
    /// Previous modifier state, used to detect modifier key-down transitions.
    private var previousModifierFlags: NSEvent.ModifierFlags = []

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, onActivate: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers
        self.onActivate = onActivate
        register()
    }

    func update(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        unregister()
        self.keyCode = keyCode
        self.modifierFlags = modifiers
        self.lastPressTime = .distantPast
        self.previousModifierFlags = []
        register()
    }

    // MARK: - Private

    private static let relevantModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    /// Sentinel value meaning "modifier-only" (no key involved). UInt16.max is never a real key code.
    static let modifierOnlySentinel: UInt16 = UInt16.max

    private func register() {
        if keyCode == Self.modifierOnlySentinel {
            // Modifier-only double-tap: listen to flagsChanged
            let handler: (NSEvent) -> Void = { [weak self] event in self?.handleFlagsChanged(event) }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
                self?.handleFlagsChanged(event); return event
            }) { monitors.append(m) }
        } else {
            // Modifier + key double-tap: listen to keyDown
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
                self?.handleKeyDown(event)
            }) { monitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
                guard self?.matchesKeyDown(event) == true else { return event }
                self?.handleDoubleTap()
                return nil // consume
            }) { monitors.append(m) }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let current = event.modifierFlags.intersection(Self.relevantModifiers)
        let previous = previousModifierFlags
        previousModifierFlags = current

        // Detect: target modifier(s) just became active (key-down transition), nothing extra held
        let targetJustPressed = current.contains(modifierFlags) && !previous.contains(modifierFlags)
        let noExtraModifiers = current == modifierFlags
        guard targetJustPressed && noExtraModifiers else { return }
        handleDoubleTap()
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard matchesKeyDown(event) else { return }
        handleDoubleTap()
    }

    private func matchesKeyDown(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode &&
        event.modifierFlags.intersection(Self.relevantModifiers) == modifierFlags
    }

    private func handleDoubleTap() {
        let now = Date()
        if now.timeIntervalSince(lastPressTime) <= doubleTapWindow {
            lastPressTime = .distantPast // reset to prevent triple-tap triggering again
            DispatchQueue.main.async { [weak self] in self?.onActivate() }
        } else {
            lastPressTime = now
        }
    }

    private func unregister() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    deinit { unregister() }
}
