import Foundation

class CopilotFeature {
    private let ollama: OllamaClient
    private let panel: FloatingPanel
    private var context: String = ""
    private var activeTask: Task<Void, Never>?

    init(ollama: OllamaClient, panel: FloatingPanel) {
        self.ollama = ollama
        self.panel = panel
        loadContext()
    }

    func query(_ text: String) {
        activeTask?.cancel()
        activeTask = nil

        panel.clearCopilot()
        panel.showCopilot(query: text)

        let ctx = context
        let ollama = self.ollama
        let panel = self.panel
        activeTask = Task {
            await ollama.searchKnowledgeBase(
                query: text,
                context: ctx,
                onChunk: { chunk in
                    guard !Task.isCancelled else { return }
                    panel.streamCopilotChunk(chunk)
                },
                onComplete: {}
            )
        }
    }

    private func loadContext() {
        if let url = Bundle.main.url(forResource: "interview_context", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            context = content
            return
        }
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let fallback = execDir.appendingPathComponent("interview_context.txt")
        if let content = try? String(contentsOf: fallback, encoding: .utf8) {
            context = content
            return
        }
        context = "No context loaded."
    }
}
