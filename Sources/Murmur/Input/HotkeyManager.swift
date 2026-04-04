import AppKit
import Carbon

class HotkeyManager {
    private var monitors: [Any] = []
    private let onActivate: () -> Void
    private var keyCode: UInt16
    private var modifierFlags: NSEvent.ModifierFlags

    init(keyCode: UInt16 = 49, modifiers: NSEvent.ModifierFlags = .option, onActivate: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers
        self.onActivate = onActivate
        register()
    }

    func update(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers
    }

    private func register() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if self?.matches(e) == true { DispatchQueue.main.async { self?.onActivate() } }
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard self?.matches(e) == true else { return e }
            DispatchQueue.main.async { self?.onActivate() }
            return nil
        }) { monitors.append(m) }
    }

    private func matches(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifierFlags
            && event.keyCode == keyCode
    }

    deinit { monitors.forEach { NSEvent.removeMonitor($0) } }
}
