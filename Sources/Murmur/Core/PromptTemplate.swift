import Foundation

struct PromptTemplate: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var promptInstruction: String?  // nil = no style override (auto mode)

    static let builtins: [PromptTemplate] = [
        .init(id: "auto",      name: "润色",      promptInstruction: nil),
        .init(id: "formal",    name: "正式",      promptInstruction: "语气正式，用词严谨，适合商务或官方场合。"),
        .init(id: "concise",   name: "简洁",      promptInstruction: "尽量精简，去掉冗余，保留核心意思。"),
        .init(id: "ai_prompt", name: "AI 提示词", promptInstruction: "改写为适合发送给 AI 的提示词：意图明确、结构清晰、包含必要上下文、去除口语化表达，必要时拆解为背景/任务/要求三部分。"),
    ]
}
