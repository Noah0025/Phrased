import SwiftUI

extension SettingsView {
    var vocabularyPane: some View {
        VStack(spacing: 0) {
            Text("settings.vocabulary.description")
                .font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top])

            List {
                ForEach($vocabWords) { $entry in
                    HStack(spacing: PhrasedSpacing.sm) {
                        TextField("settings.vocabulary.trigger", text: $entry.trigger)
                            .frame(width: 100)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, PhrasedSpacing.sm)
                            .padding(.vertical, PhrasedSpacing.xs)
                            .background(Color(NSColor.controlBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: PhrasedRadius.sm).stroke(Color.primary.opacity(PhrasedOpacity.border), lineWidth: 1))
                        Text("→").foregroundColor(.secondary)
                        TextField("settings.vocabulary.expand_to", text: $entry.expansion)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, PhrasedSpacing.sm)
                            .padding(.vertical, PhrasedSpacing.xs)
                            .background(Color(NSColor.controlBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: PhrasedRadius.sm).stroke(Color.primary.opacity(PhrasedOpacity.border), lineWidth: 1))
                        Button {
                            if let idx = vocabWords.firstIndex(where: { $0.id == entry.id }) {
                                vocabWords.remove(at: idx)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(PhrasedFont.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("settings.model.add") {
                    vocabWords.append(VocabEntry(trigger: "", expansion: ""))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .listRowSeparator(.hidden)
            }
        }
        .onChange(of: vocabWords) { words in
            try? VocabularyStore(words: words).save()
        }
        .navigationTitle("settings.vocabulary.navigation_title")
    }
}
