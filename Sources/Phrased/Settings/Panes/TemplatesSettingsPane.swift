import SwiftUI

extension SettingsView {
    // MARK: - Templates

    var templatesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach($draft.editedBuiltins) { $t in
                    templateRow(template: $t, isBuiltin: true,
                                defaultTemplate: PromptTemplate.builtins.first { $0.id == t.id },
                                onDelete: nil)
                }
                ForEach($draft.customTemplates) { $t in
                    let idx = draft.customTemplates.firstIndex { $0.id == t.id }
                    templateRow(template: $t, isBuiltin: false, defaultTemplate: nil,
                                onDelete: idx.map { i in { draft.customTemplates.remove(at: i) } })
                }
                Button("settings.templates.add") {
                    let t = PromptTemplate(id: UUID().uuidString, name: "", promptInstruction: "")
                    draft.customTemplates.append(t)
                    expandedTemplateIDs.insert(t.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
        }
        .navigationTitle("settings.templates.navigation_title")
    }

    @ViewBuilder
    func templateRow(
        template: Binding<PromptTemplate>,
        isBuiltin: Bool,
        defaultTemplate: PromptTemplate?,
        onDelete: (() -> Void)?
    ) -> some View {
        let t = template.wrappedValue
        let isExpanded = expandedTemplateIDs.contains(t.id)
        let isModified = isBuiltin && (t.name != defaultTemplate?.name || t.promptInstruction != defaultTemplate?.promptInstruction)

        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded { expandedTemplateIDs.remove(t.id) }
                    else { expandedTemplateIDs.insert(t.id) }
                }
            } label: {
                HStack {
                    Text(t.name.isEmpty ? String(localized: "settings.model.unnamed") : t.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    if isModified, let def = defaultTemplate {
                        Button {
                            template.wrappedValue.name = def.name
                            template.wrappedValue.promptInstruction = def.promptInstruction
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(PhrasedFont.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "settings.templates.help.restore_default"))
                    }
                    if let del = onDelete {
                        Button { del() } label: {
                            Image(systemName: "trash")
                                .font(PhrasedFont.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "settings.help.delete"))
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(PhrasedFont.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    profileFieldRow(label: String(localized: "settings.field.name"), content: {
                        TextField("", text: template.name, prompt: Text("settings.templates.placeholder.template_name"))
                            .font(PhrasedFont.secondary)
                    })
                    Divider()
                    profileFieldRow(label: String(localized: "settings.templates.field.prompt"), content: {
                        TextField("", text: Binding(
                            get: { template.wrappedValue.promptInstruction ?? "" },
                            set: { template.wrappedValue.promptInstruction = $0.isEmpty ? nil : $0 }
                        ), prompt: Text("settings.templates.placeholder.default_mode"), axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .font(PhrasedFont.secondary)
                    })
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12 as Double), lineWidth: 1))
    }
}
