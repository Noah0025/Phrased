import Foundation

class IntentProcessor {
    func buildMessages(
        input: String,
        feedback: String?,
        template: PromptTemplate = PromptTemplate.builtins[0],
        context: InputContext = .empty
    ) -> [LLMMessage] {
        var styleInstruction = ""
        if let instruction = template.promptInstruction {
            styleInstruction = "\n风格要求：\(instruction)"
        }

        var contextBlock = ""
        if let selected = context.selectedText, !selected.isEmpty {
            contextBlock += "\n\n用户当前选中的文字（可作为参考上下文）：\n\(selected)"
        }
        if let clip = context.clipboardText, !clip.isEmpty, clip != input {
            contextBlock += "\n\n用户剪贴板内容：\n\(clip)"
        }
        if let appName = context.frontmostAppName {
            contextBlock += "\n\n来源应用：\(appName)"
        }

        var userContent = """
        你是用户的个人语言助手。
        将以下输入理解为用户的真实意图，改写为清晰、准确、适合直接使用的文字。
        保持简洁，只输出改写后的文字，不要添加多余解释。\(styleInstruction)\(contextBlock)

        用户输入：\(input)
        """

        if let feedback, !feedback.isEmpty {
            userContent += "\n\n用户对上一次结果不满意，补充说明：\(feedback)\n\n请重新生成。"
        }

        return [LLMMessage(role: "user", content: userContent)]
    }
}
