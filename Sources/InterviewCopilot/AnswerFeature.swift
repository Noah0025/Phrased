import Foundation

class AnswerFeature {
    private let transcriber: SpeechTranscriber
    private let ollama: OllamaClient
    private let panel: FloatingPanel
    private var interviewContext: String = ""
    private var isGenerating = false

    init(transcriber: SpeechTranscriber, ollama: OllamaClient, panel: FloatingPanel) {
        self.transcriber = transcriber
        self.ollama = ollama
        self.panel = panel
        loadContext()
    }

    func trigger() {
        guard !isGenerating else { return }
        isGenerating = true
        panel.clearAnswer()
        panel.setAnswerLoading(true)

        let question = transcriber.recentTranscript(lastSegments: 3)
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else {
            panel.setAnswerLoading(false)
            isGenerating = false
            return
        }

        ollama.suggestAnswer(
            question: question,
            context: interviewContext,
            onChunk: { [weak self] chunk in
                self?.panel.appendAnswerChunk(chunk)
            },
            onComplete: { [weak self] in
                self?.panel.setAnswerLoading(false)
                self?.isGenerating = false
            }
        )
    }

    private func loadContext() {
        // Try bundle resource first
        if let url = Bundle.main.url(forResource: "interview_context", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            interviewContext = content
            return
        }
        // Fallback: look next to the executable
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let fallback = execDir.appendingPathComponent("interview_context.txt")
        if let content = try? String(contentsOf: fallback, encoding: .utf8) {
            interviewContext = content
            return
        }
        interviewContext = "No interview context loaded."
    }
}
