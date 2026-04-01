import Foundation

struct KnowledgeSection {
    let title: String
    let body: String
}

class KnowledgeBase {
    private let ollama: OllamaClient
    private(set) var sections: [KnowledgeSection] = []

    init(ollama: OllamaClient) {
        self.ollama = ollama
        loadSections()
    }

    // MARK: - Loading

    private func loadSections() {
        guard let content = loadFile() else { return }
        sections = parse(content)
    }

    private func loadFile() -> String? {
        if let url = Bundle.main.url(forResource: "interview_context", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let fallback = execDir.appendingPathComponent("interview_context.txt")
        return try? String(contentsOf: fallback, encoding: .utf8)
    }

    private func parse(_ markdown: String) -> [KnowledgeSection] {
        var result: [KnowledgeSection] = []
        var currentTitle: String? = nil
        var currentLines: [String] = []

        func flush() {
            guard let title = currentTitle else { return }
            let body = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                result.append(KnowledgeSection(title: title, body: body))
            }
        }

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentLines = []
            } else if line.hasPrefix("# ") {
                // Top-level heading — not a retrievable section
                continue
            } else if currentTitle != nil {
                currentLines.append(line)
            }
        }
        flush()
        return result
    }

    // MARK: - Retrieval

    /// Returns the most relevant section for `query`, or nil if no sections loaded.
    func retrieve(query: String) async -> KnowledgeSection? {
        guard !sections.isEmpty else { return nil }
        guard sections.count > 1 else { return sections[0] }

        let titles = sections.enumerated()
            .map { "\($0.offset + 1). \($0.element.title)" }
            .joined(separator: "\n")

        let prompt = """
        You are helping find relevant interview prep material.
        Statement heard: "\(query)"

        Available sections:
        \(titles)

        Reply with ONLY the number of the most relevant section.
        """

        let response = await ollama.complete(prompt: prompt)
        let idx = parseIndex(from: response, max: sections.count)
        return sections[idx]
    }

    private func parseIndex(from response: String, max: Int) -> Int {
        let words = response.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            if let n = Int(clean), n >= 1, n <= max {
                return n - 1
            }
        }
        return 0
    }
}
