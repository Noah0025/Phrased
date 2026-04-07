import Foundation

struct PromptTemplate: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var promptInstruction: String?  // nil = no style override (auto mode)

    static let builtins: [PromptTemplate] = [
        .init(id: "auto",      name: NSLocalizedString("prompt.template.polish", comment: ""),    promptInstruction: nil),
        .init(id: "formal",    name: NSLocalizedString("prompt.template.formal", comment: ""),    promptInstruction: NSLocalizedString("prompt.instruction.formal", comment: "")),
        .init(id: "concise",   name: NSLocalizedString("prompt.template.concise", comment: ""),   promptInstruction: NSLocalizedString("prompt.instruction.concise", comment: "")),
        .init(id: "ai_prompt", name: NSLocalizedString("prompt.template.ai_prompt", comment: ""), promptInstruction: NSLocalizedString("prompt.instruction.ai_prompt", comment: "")),
    ]
}
