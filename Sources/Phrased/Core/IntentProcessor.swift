import Foundation

class IntentProcessor {
    private func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    func buildMessages(
        input: String,
        feedback: String?,
        template: PromptTemplate = PromptTemplate.builtins[0],
        context: InputContext = .empty
    ) -> [LLMMessage] {
        // System message: template instruction, or auto-generated from context app
        var systemContent = ""
        if let instruction = template.promptInstruction {
            systemContent = instruction
        } else if let appName = context.frontmostAppName, !appName.isEmpty {
            let format = NSLocalizedString("prompt.instruction.auto", comment: "")
            systemContent = String(format: format, appName)
        } else {
            systemContent = NSLocalizedString("prompt.instruction.auto.base", comment: "")
        }

        // User message: structured context + input, language-neutral tags
        var userContent = ""
        if let selected = context.selectedText, !selected.isEmpty {
            userContent += "<context>\(xmlEscape(selected))</context>\n\n"
        }
        if let appName = context.frontmostAppName, !appName.isEmpty {
            userContent += "<app>\(xmlEscape(appName))</app>\n\n"
        }
        userContent += input
        if let feedback, !feedback.isEmpty {
            userContent += "\n\n<feedback>\(xmlEscape(feedback))</feedback>"
        }

        var messages: [LLMMessage] = []
        if !systemContent.isEmpty {
            messages.append(LLMMessage(role: .system, content: systemContent))
        }
        messages.append(LLMMessage(role: .user, content: userContent))
        return messages
    }
}
