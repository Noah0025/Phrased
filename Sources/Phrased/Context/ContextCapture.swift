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
            "com.tencent.xinWeChat":          "concise",
            "com.apple.Notes":                "auto",
            "com.notion.id":                  "formal",
            "com.linear.app":                 "concise",
            "com.github.GitHubDesktop":       "concise",
            "com.openai.chat":                "ai_prompt",
            "com.anthropic.claudefordesktop": "ai_prompt",
        ]
        return map[bundleID]
    }
}

enum ContextCapture {
    /// Must be called BEFORE the Phrased window is activated (while the user's app is still frontmost).
    static func capture() -> InputContext {
        let app = NSWorkspace.shared.frontmostApplication
        let selected = selectedTextViaAccessibility(for: app)
        return InputContext(frontmostApp: app, selectedText: selected, clipboardText: sanitizedClipboard())
    }

    private static func sanitizedClipboard() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return nil }
        let text = String(raw.prefix(500))
        guard !text.isEmpty else { return nil }
        guard !looksSensitive(text) else { return nil }
        return text
    }

    private static func looksSensitive(_ text: String) -> Bool {
        if text.hasPrefix("sk-") || text.hasPrefix("ghp_") || text.hasPrefix("eyJ") {
            return true
        }

        guard !text.contains(where: \.isWhitespace) else { return false }
        guard text.count > 20 else { return false }

        let alphanumericCount = text.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                count += 1
            }
        }
        return Double(alphanumericCount) / Double(text.count) >= 0.85
    }

    private static func selectedTextViaAccessibility(for app: NSRunningApplication?) -> String? {
        guard AXIsProcessTrusted(), let app else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else { return nil }
        // CoreFoundation bridged type: cast always succeeds per AX API contract
        let axElement = element as! AXUIElement
        var selectedText: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextAttribute as CFString, &selectedText
        )
        guard result == .success, let text = selectedText as? String, !text.isEmpty else { return nil }
        return text
    }
}
