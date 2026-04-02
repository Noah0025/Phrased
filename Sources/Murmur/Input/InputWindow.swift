import SwiftUI
import AppKit

@MainActor
class InputViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isRecording: Bool = false
    @Published var partialTranscript: String = ""

    var onSubmit: ((String) -> Void)?

    private let audioCapture = AudioCapture()
    private let transcriber = SpeechTranscriber()

    init() {
        transcriber.onPartial = { [weak self] text in
            DispatchQueue.main.async {
                self?.partialTranscript = text
            }
        }
        transcriber.onFinal = { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inputText = text
                self.partialTranscript = ""
                self.stopRecording()
            }
        }
    }

    func submit() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSubmit?(text)
        inputText = ""
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        inputText = ""
        partialTranscript = ""
        transcriber.startSession()
        audioCapture.start { [weak self] buffer in
            self?.transcriber.appendBuffer(buffer)
        }
    }

    private func stopRecording() {
        isRecording = false
        audioCapture.stop()
        transcriber.stopSession()
    }
}

struct InputView: View {
    @ObservedObject var vm: InputViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            // Display area: shows partial transcript while recording, editable text otherwise
            if vm.isRecording {
                Text(vm.partialTranscript.isEmpty ? "正在聆听..." : vm.partialTranscript)
                    .foregroundColor(vm.partialTranscript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                    .frame(height: 60)
            } else {
                TextEditor(text: $vm.inputText)
                    .font(.body)
                    .padding(4)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .frame(height: 60)
                    .focused($isFocused)
            }

            HStack {
                // Mic button
                Button {
                    vm.toggleRecording()
                } label: {
                    Image(systemName: vm.isRecording ? "stop.circle.fill" : "mic.circle")
                        .font(.title2)
                        .foregroundColor(vm.isRecording ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help(vm.isRecording ? "停止录音" : "开始录音")

                Spacer()

                Button("取消") {
                    NSApp.keyWindow?.orderOut(nil)
                }
                .keyboardShortcut(.escape)

                Button("改写 →") {
                    vm.submit()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isRecording)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(width: 400)
        .onAppear { isFocused = true }
    }
}

class InputWindowController: NSWindowController {
    private let vm: InputViewModel

    init(vm: InputViewModel) {
        self.vm = vm
        let view = InputView(vm: vm)
        let hosting = NSHostingController(rootView: view)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "Murmur"
        window.contentViewController = hosting
        (window as? NSPanel)?.isFloatingPanel = true
        window.level = .floating
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
