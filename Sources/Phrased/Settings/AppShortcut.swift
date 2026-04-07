import Foundation

struct AppShortcut: Codable, Identifiable, Equatable {
    var id: String          // stable key: "transcribe", "pin", etc.
    var name: String        // localized display name
    // keyCode 0 = physical A key, UInt16.max = disabled/unbound sentinel.
    var keyCode: UInt16     // physical key code; UInt16.max disables/unbinds
    var modifiers: [String] // ["command"], ["command", "shift"], or [] for bare key

    // MARK: - Defaults

    static let defaults: [AppShortcut] = [
        AppShortcut(id: "transcribe",   name: NSLocalizedString("shortcut.default.transcribe", comment: ""), keyCode: 0, modifiers: ["command", "shift"]), // ⌘⇧A
        AppShortcut(id: "submit",       name: NSLocalizedString("shortcut.default.submit", comment: ""), keyCode: 36, modifiers: ["command"]), // ⌘↩
        AppShortcut(id: "newline",      name: NSLocalizedString("shortcut.default.newline", comment: ""), keyCode: 36, modifiers: []), // ↩
        AppShortcut(id: "pin",          name: NSLocalizedString("shortcut.default.pin", comment: ""), keyCode: 35, modifiers: ["command"]), // ⌘P
        AppShortcut(id: "edit",         name: NSLocalizedString("shortcut.default.edit", comment: ""), keyCode: 14, modifiers: ["command"]), // ⌘E
        AppShortcut(id: "regenerate",   name: NSLocalizedString("shortcut.default.regenerate", comment: ""), keyCode: 15, modifiers: ["command"]), // ⌘R
        AppShortcut(id: "inject",       name: NSLocalizedString("shortcut.default.inject", comment: ""), keyCode: 34, modifiers: ["command"]), // ⌘I
    ]
}
