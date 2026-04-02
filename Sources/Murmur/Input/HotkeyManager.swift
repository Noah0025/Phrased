import AppKit
import Carbon

class HotkeyManager {
    private var monitors: [Any] = []
    private let onActivate: () -> Void

    init(onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
        register()
    }

    private func register() {
        // Global monitor (works when other apps are focused)
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if self?.isActivationHotkey(event) == true {
                DispatchQueue.main.async { self?.onActivate() }
            }
        }) {
            monitors.append(monitor)
        }

        // Local monitor (when Murmur is focused)
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if self?.isActivationHotkey(event) == true {
                DispatchQueue.main.async { self?.onActivate() }
                return nil
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// ⌥Space: keyCode 49 (Space), modifier .option
    private func isActivationHotkey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .option && event.keyCode == 49
    }

    deinit {
        monitors.forEach { NSEvent.removeMonitor($0) }
    }
}
