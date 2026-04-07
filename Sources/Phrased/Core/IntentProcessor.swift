import Foundation

class IntentProcessor {
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
        }

        // User message: structured context + input, language-neutral tags
        var userContent = ""
        if let selected = context.selectedText, !selected.isEmpty {
            userContent += "<context>\(selected)</context>\n\n"
        }
        if let appName = context.frontmostAppName, !appName.isEmpty {
            userContent += "<app>\(appName)</app>\n\n"
        }
        userContent += input
        if let feedback, !feedback.isEmpty {
            userContent += "\n\n<feedback>\(feedback)</feedback>"
        }

        var messages: [LLMMessage] = []
        if !systemContent.isEmpty {
            messages.append(LLMMessage(role: .system, content: systemContent))
        }
        messages.append(LLMMessage(role: .user, content: userContent))
        return messages
    }
}
