import Foundation

class IntentProcessor {
    private(set) var profile: UserProfile

    init(profile: UserProfile = UserProfile.loadOrDefault()) {
        self.profile = profile
    }

    func updateProfile(_ profile: UserProfile) {
        self.profile = profile
    }

    /// Build messages array for Ollama. System message is only included when profile has data.
    func buildMessages(input: String, feedback: String?) -> [OllamaMessage] {
        var messages: [OllamaMessage] = []

        if !profile.isEmpty {
            let systemContent = """
            你是用户的个人语言助手。以下是用户的语言偏好与习惯：
            \(profileDescription())
            将用户的原始输入理解为真实意图，改写为清晰、准确的文字。
            输出语言：\(profile.preferredOutputLanguage)
            """
            messages.append(OllamaMessage(role: "system", content: systemContent))
        }

        var userContent = """
        你是用户的个人语言助手。
        将以下输入理解为用户的真实意图，改写为清晰、准确、适合直接使用的文字。
        保持简洁，只输出改写后的文字，不要添加多余解释。

        用户输入：\(input)
        """

        if let feedback, !feedback.isEmpty {
            userContent += "\n\n用户对上一次结果不满意，补充说明：\(feedback)\n\n请重新生成。"
        }

        messages.append(OllamaMessage(role: "user", content: userContent))
        return messages
    }

    private func profileDescription() -> String {
        var parts: [String] = []
        if !profile.tone.isEmpty { parts.append("语气：\(profile.tone)") }
        if !profile.formality.isEmpty { parts.append("正式程度：\(profile.formality)") }
        if let summary = profile.historySummary { parts.append("习惯摘要：\(summary)") }
        return parts.joined(separator: "\n")
    }
}
