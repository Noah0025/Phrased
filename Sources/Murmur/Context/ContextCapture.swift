import AppKit
import ApplicationServices

struct InputContext {
    var frontmostApp: NSRunningApplication?
    var frontmostAppName: String? { frontmostApp?.localizedName }
    var frontmostAppBundleID: String? { frontmostApp?.bundleIdentifier }
    var selectedText: String?
    var clipboardText: String?

    var isEmpty: Bool {
        frontmostApp == nil && selectedText == nil && clipboardText == nil
    }

    static let empty = InputContext(frontmostApp: nil, selectedText: nil, clipboardText: nil)

    /// Suggest a template ID based on the frontmost app.
    var suggestedTemplateID: String? {
        guard let bundleID = frontmostAppBundleID else { return nil }
        let map: [String: String] = [
            "com.apple.mail":                 "formal",
            "com.microsoft.Outlook":          "formal",
            "com.tencent.xinWeChat":          "polite",
            "com.apple.Notes":                "casual",
            "com.notion.id":                  "professional",
            "com.linear.app":                 "professional",
            "com.github.GitHubDesktop":       "concise",
            "com.openai.chat":                "ai_prompt",
            "com.anthropic.claudefordesktop": "ai_prompt",
        ]
        return map[bundleID]
    }
}

enum ContextCapture {
    /// Must be called BEFORE Murmur window is activated (while user's app is still frontmost).
    static func capture() -> InputContext {
        let app = NSWorkspace.shared.frontmostApplication
        let selected = selectedTextViaAccessibility(for: app)
        return InputContext(frontmostApp: app, selectedText: selected, clipboardText: nil)
    }

    private static func selectedTextViaAccessibility(for app: NSRunningApplication?) -> String? {
        guard AXIsProcessTrusted(), let app else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else { return nil }
        var selectedText: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText
        )
        guard result == .success, let text = selectedText as? String, !text.isEmpty else { return nil }
        return text
    }
}
