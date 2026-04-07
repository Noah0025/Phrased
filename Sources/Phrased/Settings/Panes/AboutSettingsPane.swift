import SwiftUI

extension SettingsView {
    var aboutPane: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"

        return VStack(spacing: PhrasedSpacing.lg) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            Text("Phrased")
                .font(.title2.bold())
            Text(String(format: String(localized: "settings.about.version_format"), version, build))
                .foregroundColor(.secondary)
            Text(Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("settings.about.view_on_github") {
                NSWorkspace.shared.open(URL(string: "https://github.com/helms-project/phrased")!)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PhrasedSpacing.xxl)
    }
}
