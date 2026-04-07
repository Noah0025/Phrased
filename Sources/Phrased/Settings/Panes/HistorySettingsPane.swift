import SwiftUI

extension SettingsView {
    var historyPane: some View {
        Form {
            Section {
                Picker("settings.history.default_grouping", selection: $draft.historyGroupMode) {
                    ForEach(HistoryGroupMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
            } header: {
                Text("settings.history.grouping")
            } footer: {
                Text("settings.history.grouping_note")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section {
                Picker("settings.history.retention_period", selection: $draft.historyRetentionDays) {
                    Text("settings.history.retention.30_days").tag(30)
                    Text("settings.history.retention.90_days").tag(90)
                    Text("settings.history.retention.180_days").tag(180)
                    Text("settings.history.retention.1_year").tag(365)
                    Text("settings.history.retention.forever").tag(0)
                }
            } header: {
                Text("settings.history.retention")
            } footer: {
                Text("settings.history.retention_note")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section {
                HStack {
                    Button("settings.history.open") { onOpenHistory?() }
                    Spacer()
                    Button("settings.history.export") { onExportHistory?() }
                }
            } header: {
                Text("settings.history.actions")
            } footer: {
                Text("settings.history.export_note")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("settings.section.history")
    }
}
