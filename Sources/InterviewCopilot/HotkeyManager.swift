import AppKit
import Carbon

class HotkeyManager {
    private var monitors: [Any] = []
    private let onToggleListen: () -> Void
    private let onSuggestAnswer: () -> Void

    init(onToggleListen: @escaping () -> Void, onSuggestAnswer: @escaping () -> Void) {
        self.onToggleListen = onToggleListen
        self.onSuggestAnswer = onSuggestAnswer
        registerGlobalHotkeys()
    }

    private func registerGlobalHotkeys() {
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Cmd+Shift+S → toggle listening
            if flags == [.command, .shift] && event.keyCode == 1 { // keyCode 1 = S
                DispatchQueue.main.async { self.onToggleListen() }
            }
            // Cmd+Shift+A → suggest answer
            if flags == [.command, .shift] && event.keyCode == 0 { // keyCode 0 = A
                DispatchQueue.main.async { self.onSuggestAnswer() }
            }
        }
        if let monitor { monitors.append(monitor) }

        // Also add local monitor (when app is focused)
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command, .shift] && event.keyCode == 1 {
                DispatchQueue.main.async { self.onToggleListen() }
                return nil
            }
            if flags == [.command, .shift] && event.keyCode == 0 {
                DispatchQueue.main.async { self.onSuggestAnswer() }
                return nil
            }
            return event
        }
        if let localMonitor { monitors.append(localMonitor) }
    }

    deinit {
        monitors.forEach { NSEvent.removeMonitor($0) }
    }
}
