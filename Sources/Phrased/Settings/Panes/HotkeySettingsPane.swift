import SwiftUI

extension SettingsView {
    static let defaultHotkeyKeyCode: UInt16 = UInt16.max
    static let defaultHotkeyModifiers: [String] = ["control"]

    var hotkeyPane: some View {
        Form {
            Section(header: Text("settings.hotkey.global"), footer: Text("settings.hotkey.global.footer").font(.caption).foregroundColor(.secondary)) {
                shortcutRow(
                    label: String(localized: "settings.hotkey.open_phrased"),
                    keyCode: $draft.hotkeyKeyCode,
                    modifiers: $draft.hotkeyModifiers,
                    defaultKeyCode: Self.defaultHotkeyKeyCode,
                    defaultModifiers: Self.defaultHotkeyModifiers,
                    requiresModifier: true,
                    allowModifierOnly: true,
                    showDoubleTap: true,
                    helpText: String(localized: "settings.hotkey.restore_default_double_control")
                )
            }

            Section(header: Text("settings.hotkey.in_app"), footer: Text("settings.hotkey.in_app.footer").font(.caption).foregroundColor(.secondary)) {
                ForEach($draft.appShortcuts) { $shortcut in
                    let def = AppShortcut.defaults.first { $0.id == shortcut.id }
                    shortcutRow(
                        label: shortcut.name,
                        keyCode: $shortcut.keyCode,
                        modifiers: $shortcut.modifiers,
                        defaultKeyCode: def?.keyCode ?? shortcut.keyCode,
                        defaultModifiers: def?.modifiers ?? shortcut.modifiers,
                        requiresModifier: false,
                        allowModifierOnly: false,
                        showDoubleTap: false,
                        helpText: String(localized: "settings.hotkey.restore_default")
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("settings.section.hotkey")
    }

    @ViewBuilder
    func shortcutRow(
        label: String,
        keyCode: Binding<UInt16>,
        modifiers: Binding<[String]>,
        defaultKeyCode: UInt16,
        defaultModifiers: [String],
        requiresModifier: Bool,
        allowModifierOnly: Bool,
        showDoubleTap: Bool,
        helpText: String
    ) -> some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            ShortcutRecorderView(
                keyCode: keyCode,
                modifiers: modifiers,
                requiresModifier: requiresModifier,
                allowModifierOnly: allowModifierOnly,
                showDoubleTap: showDoubleTap
            )
            .frame(width: 120, height: 26)
            Button {
                keyCode.wrappedValue = defaultKeyCode
                modifiers.wrappedValue = defaultModifiers
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help(helpText)
        }
    }
}
