import SwiftUI
import AppKit

struct ConfirmView: View {
    @ObservedObject var vm: ConfirmViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Original input
            VStack(alignment: .leading, spacing: 4) {
                Text("原始输入")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(vm.originalInput)
                    .font(.body)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
            }

            // Streamed result
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("改写结果")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if vm.isStreaming {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    }
                }
                ScrollView {
                    Text(vm.streamedResult.isEmpty && vm.isStreaming ? "正在生成..." : vm.streamedResult)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(vm.streamedResult.isEmpty ? .secondary : .primary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 160)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }

            // Feedback field (shown on demand)
            if vm.showFeedbackField {
                VStack(alignment: .leading, spacing: 4) {
                    Text("修改意见")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        TextField("说明哪里不对，或者想要什么效果...", text: $vm.feedbackText)
                            .textFieldStyle(.roundedBorder)
                        Button("重新生成") {
                            vm.regenerate()
                        }
                        .disabled(vm.isStreaming)
                    }
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                Button("取消") {
                    vm.cancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("修改意见") {
                    vm.showFeedbackField.toggle()
                }
                .disabled(vm.isStreaming)

                Button("重新生成") {
                    vm.regenerate()
                }
                .disabled(vm.isStreaming)

                Button(vm.didCopy ? "已复制 ✓" : "接受并复制") {
                    vm.accept()
                }
                .keyboardShortcut(.return)
                .disabled(vm.isStreaming || vm.streamedResult.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 480)
    }
}

class ConfirmWindowController: NSWindowController {
    private let vm: ConfirmViewModel

    init(vm: ConfirmViewModel) {
        self.vm = vm
        let view = ConfirmView(vm: vm)
        let hosting = NSHostingController(rootView: view)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "Murmur"
        window.contentViewController = hosting
        window.isFloatingPanel = true
        window.level = .floating
        window.center()
        super.init(window: window)
        vm.onDismiss = { [weak self] in
            self?.close()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func present(input: String) {
        vm.start(input: input)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
