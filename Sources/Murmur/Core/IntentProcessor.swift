import Foundation

enum WritingStyle: String, CaseIterable, Identifiable {
    case auto     = "通用"
    case formal   = "正式"
    case concise  = "简洁"
    case casual   = "随性"
    case professional = "专业"
    case polite   = "礼貌"
    case aiPrompt = "AI 提示词"

    var id: String { rawValue }

    var promptInstruction: String? {
        switch self {
        case .auto:         return nil
        case .formal:       return "语气正式，用词严谨，适合商务或官方场合。"
        case .concise:      return "尽量精简，去掉冗余，保留核心意思。"
        case .casual:       return "语气轻松随意，像朋友之间说话。"
        case .professional: return "专业术语准确，逻辑清晰，适合行业内沟通。"
        case .polite:       return "措辞礼貌周到，态度温和。"
        case .aiPrompt:     return "改写为适合发送给 AI 的提示词：意图明确、结构清晰、包含必要上下文、去除口语化表达，必要时拆解为背景/任务/要求三部分。"
        }
    }
}

class IntentProcessor {
    private(set) var profile: UserProfile

    init(profile: UserProfile = UserProfile.loadOrDefault()) {
        self.profile = profile
    }

    func updateProfile(_ profile: UserProfile) {
        self.profile = profile
    }

    /// Build messages array for Ollama. System message is only included when profile has data.
    func buildMessages(input: String, feedback: String?, style: WritingStyle = .auto) -> [OllamaMessage] {
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

        var styleInstruction = ""
        if let instruction = style.promptInstruction {
            styleInstruction = "\n风格要求：\(instruction)"
        }

        var userContent = """
        你是用户的个人语言助手。
        将以下输入理解为用户的真实意图，改写为清晰、准确、适合直接使用的文字。
        保持简洁，只输出改写后的文字，不要添加多余解释。\(styleInstruction)

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
