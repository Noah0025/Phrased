import Foundation

struct AppShortcut: Codable, Identifiable, Equatable {
    var id: String          // stable key: "transcribe", "pin", etc.
    var name: String        // localized display name
    // keyCode 0 = physical A key, UInt16.max = disabled/unbound sentinel.
    var keyCode: UInt16     // physical key code; UInt16.max disables/unbinds
    var modifiers: [String] // ["command"], ["command", "shift"], or [] for bare key

    // MARK: - Defaults

    static let defaults: [AppShortcut] = [
        AppShortcut(id: "transcribe",   name: "开启/关闭音频识别", keyCode: 0, modifiers: ["command"]), // ⌘A
        AppShortcut(id: "submit",       name: "提交",       keyCode: 36, modifiers: ["command"]), // ⌘↩
        AppShortcut(id: "newline",      name: "换行",       keyCode: 36, modifiers: []),          // ↩
        AppShortcut(id: "pin",          name: "钉住窗口",   keyCode: 35, modifiers: ["command"]), // ⌘P
        AppShortcut(id: "edit",         name: "修改建议",   keyCode: 14, modifiers: ["command"]), // ⌘E
        AppShortcut(id: "regenerate",   name: "重新生成",   keyCode: 15, modifiers: ["command"]), // ⌘R
        AppShortcut(id: "inject",       name: "注入",       keyCode: 34, modifiers: ["command"]), // ⌘I
    ]
}
