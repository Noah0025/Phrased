import AppKit

enum TextInjector {
    /// Save clipboard → write text → activate target app → simulate ⌘V → restore clipboard after 1s.
    static func inject(_ text: String, into targetApp: NSRunningApplication?) async {
        let pasteboard = NSPasteboard.general

        // 1. Snapshot current clipboard
        let savedItems: [(types: [NSPasteboard.PasteboardType], data: [NSPasteboard.PasteboardType: Data])] =
            (pasteboard.pasteboardItems ?? []).map { item in
                let types = item.types
                var data: [NSPasteboard.PasteboardType: Data] = [:]
                types.forEach { if let d = item.data(forType: $0) { data[$0] = d } }
                return (types: types, data: data)
            }

        // 2. Write new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let changeCountAfterWrite = pasteboard.changeCount

        // 3. Activate target app
        if let app = targetApp {
            app.activate(options: [])
            try? await Task.sleep(nanoseconds: 120_000_000)  // 120ms for activation
        }

        // 4. Simulate ⌘V
        simulatePaste()

        // 5. Restore clipboard after 1 second
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard pasteboard.changeCount == changeCountAfterWrite else { return }
            pasteboard.clearContents()
            let pbItems = savedItems.map { saved -> NSPasteboardItem in
                let pbItem = NSPasteboardItem()
                saved.types.forEach { if let d = saved.data[$0] { pbItem.setData(d, forType: $0) } }
                return pbItem
            }
            pasteboard.writeObjects(pbItems)
        }
    }

    private static func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
