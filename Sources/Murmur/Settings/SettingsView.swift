import SwiftUI

struct SettingsView: View {
    @State private var draft: MurmurSettings
    private let onSave: (MurmurSettings) -> Void

    init(settings: MurmurSettings, onSave: @escaping (MurmurSettings) -> Void) {
        _draft = State(initialValue: settings)
        self.onSave = onSave
    }

    var body: some View {
        TabView {
            modelTab.tabItem     { Label("模型",   systemImage: "cpu") }
            audioTab.tabItem     { Label("音频",   systemImage: "waveform") }
            hotkeyTab.tabItem    { Label("快捷键",  systemImage: "keyboard") }
            outputTab.tabItem    { Label("输出",   systemImage: "arrow.right.doc.on.clipboard") }
            templatesTab.tabItem { Label("模板",   systemImage: "text.badge.plus") }
        }
        .padding()
        .frame(width: 500, height: 440)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("保存") { onSave(draft) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .bottom])
        }
    }

    // MARK: Model Tab

    private var modelTab: some View {
        Form {
            Section("LLM 供应商") {
                Picker("供应商", selection: $draft.llmProviderID) {
                    Text("Ollama (本地)").tag("ollama")
                    Text("OpenAI 兼容").tag("openai")
                }
                if draft.llmProviderID == "ollama" {
                    TextField("模型名称", text: $draft.ollamaModel)
                        .help("例：qwen2.5:7b, gemma3:4b, llama3.2")
                } else {
                    TextField("API 地址", text: $draft.openAIBaseURL)
                    SecureField("API Key", text: $draft.openAIAPIKey)
                    TextField("模型名称", text: $draft.openAIModel)
                }
            }
        }.formStyle(.grouped)
    }

    // MARK: Audio Tab

    private var audioTab: some View {
        Form {
            Section("音频输入源") {
                Picker("输入源", selection: $draft.audioSource) {
                    Text("系统音频（会议/视频字幕）").tag("systemAudio")
                    Text("麦克风（语音输入）").tag("microphone")
                }
                Group {
                    if draft.audioSource == "systemAudio" {
                        Text("捕获系统播放的音频。适合：转写 Zoom/Teams 会议、视频字幕。\n需要屏幕录制权限（TCC）。每次重新编译后需重新授权。")
                    } else {
                        Text("通过麦克风录制你的声音。适合：语音转文字输入。\n需要麦克风权限。")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Section("语音识别引擎") {
                Picker("ASR 引擎", selection: $draft.asrProviderID) {
                    Text("Whisper (mlx-community/whisper-small-mlx)").tag("whisper")
                }
                Text("更多引擎（SFSpeech、Whisper Large 等）将在后续版本支持。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.formStyle(.grouped)
    }

    // MARK: Hotkey Tab

    private static let modifierOptions: [(String, String)] = [
        ("option",  "⌥ Option"),
        ("command", "⌘ Command"),
        ("control", "⌃ Control"),
        ("shift",   "⇧ Shift"),
    ]

    private var hotkeyTab: some View {
        Form {
            Section("全局唤醒快捷键") {
                HStack {
                    Text("修饰键")
                    Spacer()
                    ForEach(Self.modifierOptions, id: \.0) { id, label in
                        Toggle(label, isOn: Binding(
                            get: { draft.hotkeyModifiers.contains(id) },
                            set: { on in
                                if on { draft.hotkeyModifiers.append(id) }
                                else  { draft.hotkeyModifiers.removeAll { $0 == id } }
                            }
                        )).toggleStyle(.button)
                    }
                }
                HStack {
                    Text("当前配置")
                    Spacer()
                    Text(hotkeyDescription)
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
                Text("目前按键固定为 Space（keyCode 49）。更多按键选择将在后续版本添加。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var hotkeyDescription: String {
        let m: [String: String] = ["option":"⌥","command":"⌘","control":"⌃","shift":"⇧"]
        return draft.hotkeyModifiers.compactMap { m[$0] }.joined() + "Space"
    }

    // MARK: Templates Tab

    private var templatesTab: some View {
        VStack(spacing: 0) {
            List {
                Section("内置（只读）") {
                    ForEach(PromptTemplate.builtins) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).bold()
                            Text(t.promptInstruction ?? "（无风格指令）")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Section("自定义") {
                    ForEach($draft.customTemplates) { $t in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("名称", text: $t.name)
                            TextField("提示词指令", text: Binding(
                                get: { t.promptInstruction ?? "" },
                                set: { t.promptInstruction = $0.isEmpty ? nil : $0 }
                            ), axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .font(.caption)
                        }
                    }
                    .onDelete { draft.customTemplates.remove(atOffsets: $0) }
                }
            }
            HStack {
                Spacer()
                Button("添加模板") {
                    draft.customTemplates.append(
                        PromptTemplate(id: UUID().uuidString, name: "新模板", promptInstruction: "")
                    )
                }.buttonStyle(.bordered)
            }.padding()
        }
    }

    // MARK: Output Tab

    private var outputTab: some View {
        Form {
            Section("默认输出方式") {
                Picker("接受后动作", selection: $draft.defaultOutputMode) {
                    Text("复制到剪贴板").tag("copy")
                    Text("直接注入光标位置").tag("inject")
                }
                if draft.defaultOutputMode == "inject" {
                    Text("写入剪贴板后模拟 ⌘V 注入光标。原剪贴板内容将在 1 秒后恢复。\n需要辅助功能权限（Accessibility）。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }.formStyle(.grouped)
    }
}
