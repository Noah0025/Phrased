# Knowledge Copilot Feature — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a click-to-retrieve knowledge panel — clicking a subtitle block finds and displays the most relevant section from `interview_context.txt` in an expanded right-side panel.

**Architecture:** New `KnowledgeBase` class parses Markdown into sections and queries Ollama (non-streaming) to pick the best match. `FloatingPanel` gains a collapsible right-side knowledge panel (440px ↔ 900px). `AppDelegate` wires the existing `onBlockClicked` callback to trigger retrieval.

**Tech Stack:** Swift 5.9, AppKit (NSPanel frame-based layout), Ollama gemma3:4b, SPM

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Sources/InterviewCopilot/OllamaClient.swift` | Modify | Add public `complete(prompt:)` wrapping existing private `chat()` |
| `Sources/InterviewCopilot/KnowledgeBase.swift` | **Create** | Parse Markdown sections, retrieve via Ollama |
| `Sources/InterviewCopilot/FloatingPanel.swift` | Modify | Right knowledge panel, expand/collapse logic |
| `Sources/InterviewCopilot/AppDelegate.swift` | Modify | Instantiate KnowledgeBase, wire `onBlockClicked` |

---

## Task 1: Expose `complete()` on OllamaClient

**Files:**
- Modify: `Sources/InterviewCopilot/OllamaClient.swift`

`OllamaClient` already has a private `chat(model:systemPrompt:userPrompt:stream:) async -> String?` method. We just expose it publicly.

- [ ] **Step 1: Add the method**

In `OllamaClient.swift`, after the `// MARK: - Feature 2` block and before `// MARK: - Feature 3`, insert:

```swift
// MARK: - Feature 3: Non-streaming completion (for retrieval)
/// Returns the full response as a single String. Returns "" on failure.
func complete(prompt: String) async -> String {
    return await chat(model: fastModel, systemPrompt: nil, userPrompt: prompt, stream: false) ?? ""
}
```

(Renumber existing `// MARK: - Feature 3` to `// MARK: - Feature 4`.)

- [ ] **Step 2: Verify build**

```bash
cd ~/Projects/InterviewCopilot && swift build -c release 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/InterviewCopilot/OllamaClient.swift
git commit -m "feat: expose OllamaClient.complete() for non-streaming retrieval"
```

---

## Task 2: Create KnowledgeBase.swift

**Files:**
- Create: `Sources/InterviewCopilot/KnowledgeBase.swift`

- [ ] **Step 1: Create the file**

```swift
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
        return 0  // fallback to first section
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd ~/Projects/InterviewCopilot && swift build -c release 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/InterviewCopilot/KnowledgeBase.swift
git commit -m "feat: add KnowledgeBase — Markdown parsing and Ollama-based section retrieval"
```

---

## Task 3: Add knowledge panel to FloatingPanel

**Files:**
- Modify: `Sources/InterviewCopilot/FloatingPanel.swift`

This is the largest change. We add a right-side knowledge panel that appears when `showKnowledge(title:body:)` is called and hides on `hideKnowledge()`.

- [ ] **Step 1: Add properties**

At the top of `class FloatingPanel: NSPanel`, after `private var testInputHeight: CGFloat = 0`, add:

```swift
// MARK: - Knowledge panel
private let collapsedPanelWidth: CGFloat = 440
private let expandedPanelWidth: CGFloat = 900
private var isKnowledgeExpanded = false

private let knowledgeContainer = NSView()
private let knowledgeTitleLabel = NSTextField(labelWithString: "")
private let knowledgeCloseButton = NSButton(title: "✕", target: nil, action: nil)
private let knowledgeScrollView = NSScrollView()
private let knowledgeTextView = NSTextView()
```

- [ ] **Step 2: Set up knowledge panel views in `setupUI()`**

At the end of `setupUI()`, just before the closing `}`, add:

```swift
// --- Knowledge panel (right side, hidden until first click) ---
knowledgeContainer.isHidden = true
knowledgeContainer.translatesAutoresizingMaskIntoConstraints = true
knowledgeContainer.wantsLayer = true
knowledgeContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
knowledgeContainer.layer?.cornerRadius = 8

knowledgeTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
knowledgeTitleLabel.textColor = .labelColor
knowledgeTitleLabel.translatesAutoresizingMaskIntoConstraints = true

knowledgeCloseButton.bezelStyle = .rounded
knowledgeCloseButton.font = NSFont.systemFont(ofSize: 11)
knowledgeCloseButton.target = self
knowledgeCloseButton.action = #selector(knowledgeCloseTapped)
knowledgeCloseButton.translatesAutoresizingMaskIntoConstraints = true

knowledgeTextView.isEditable = false
knowledgeTextView.isSelectable = true
knowledgeTextView.font = NSFont.systemFont(ofSize: 13)
knowledgeTextView.textColor = .labelColor
knowledgeTextView.backgroundColor = .clear
knowledgeTextView.textContainerInset = NSSize(width: 4, height: 4)
knowledgeTextView.isVerticallyResizable = true
knowledgeTextView.isHorizontallyResizable = false

knowledgeScrollView.documentView = knowledgeTextView
knowledgeScrollView.hasVerticalScroller = true
knowledgeScrollView.autohidesScrollers = true
knowledgeScrollView.borderType = .noBorder
knowledgeScrollView.backgroundColor = .clear
knowledgeScrollView.drawsBackground = false
knowledgeScrollView.translatesAutoresizingMaskIntoConstraints = true

[knowledgeTitleLabel, knowledgeCloseButton, knowledgeScrollView]
    .forEach { knowledgeContainer.addSubview($0) }
visualEffect.addSubview(knowledgeContainer)
```

- [ ] **Step 3: Add `layoutKnowledgePanel()` method**

Add this method after `layoutScrollView()`:

```swift
/// Lay out left subtitle panel (1/3) and right knowledge panel (2/3) when expanded.
private func layoutKnowledgePanel() {
    guard let cv = contentView else { return }
    let cvBounds = cv.bounds
    let totalWidth = cvBounds.width - pad * 2
    let divider: CGFloat = 8
    let leftWidth = (totalWidth - divider) / 3
    let rightWidth = totalWidth - leftWidth - divider
    let scrollBottom = bottomBar.frame.maxY + 6
    let contentHeight = max(cvBounds.height - 28 - scrollBottom, 0)

    // Subtitle scroll: left 1/3
    scrollView.frame = NSRect(x: pad, y: scrollBottom, width: leftWidth, height: contentHeight)

    // Knowledge container: right 2/3
    knowledgeContainer.frame = NSRect(
        x: pad + leftWidth + divider,
        y: scrollBottom,
        width: rightWidth,
        height: contentHeight
    )

    // Subviews inside knowledgeContainer (container-relative coords)
    let closeSize: CGFloat = 22
    let headerH: CGFloat = 26
    knowledgeCloseButton.frame = NSRect(
        x: rightWidth - closeSize - 2,
        y: contentHeight - headerH,
        width: closeSize, height: closeSize
    )
    knowledgeTitleLabel.frame = NSRect(
        x: 6,
        y: contentHeight - headerH,
        width: rightWidth - closeSize - 12, height: 20
    )
    knowledgeScrollView.frame = NSRect(
        x: 0, y: 0,
        width: rightWidth,
        height: contentHeight - headerH - 4
    )
    knowledgeTextView.frame = NSRect(
        x: 0, y: 0,
        width: rightWidth - 20,
        height: max(contentHeight - headerH - 4, 100)
    )
}
```

- [ ] **Step 4: Update `relayoutFrameBasedViews()`**

Replace the existing implementation with:

```swift
private func relayoutFrameBasedViews() {
    layoutBottomBar()
    if isKnowledgeExpanded {
        layoutKnowledgePanel()
    } else {
        layoutScrollView()
    }
    let availableWidth = scrollView.frame.width
    guard availableWidth > 0 else { return }
    stackWidthConstraint?.constant = availableWidth
}
```

- [ ] **Step 5: Add `showKnowledge()`, `hideKnowledge()`, close button action**

Add these methods in the `// MARK: - Listening state` section (after `setListeningState`):

```swift
// MARK: - Knowledge panel

func showKnowledge(title: String, body: String) {
    DispatchQueue.main.async {
        self.knowledgeTitleLabel.stringValue = title
        self.knowledgeTextView.string = body
        // Scroll to top
        self.knowledgeTextView.scrollToBeginningOfDocument(nil)

        if !self.isKnowledgeExpanded {
            self.isKnowledgeExpanded = true
            self.knowledgeContainer.isHidden = false
            var f = self.frame
            let diff = self.expandedPanelWidth - self.collapsedPanelWidth
            f.size.width = self.expandedPanelWidth
            f.origin.x -= diff  // expand leftward to stay on-screen
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.animator().setFrame(f, display: true)
            }
        }
    }
}

func hideKnowledge() {
    DispatchQueue.main.async {
        guard self.isKnowledgeExpanded else { return }
        self.isKnowledgeExpanded = false
        var f = self.frame
        let diff = self.expandedPanelWidth - self.collapsedPanelWidth
        f.size.width = self.collapsedPanelWidth
        f.origin.x += diff
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            self.animator().setFrame(f, display: true)
        }, completionHandler: {
            self.knowledgeContainer.isHidden = true
        })
    }
}

@objc private func knowledgeCloseTapped() {
    hideKnowledge()
}
```

- [ ] **Step 6: Verify build**

```bash
cd ~/Projects/InterviewCopilot && swift build -c release 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add Sources/InterviewCopilot/FloatingPanel.swift
git commit -m "feat: add expandable knowledge panel to FloatingPanel (440px ↔ 900px)"
```

---

## Task 4: Wire AppDelegate

**Files:**
- Modify: `Sources/InterviewCopilot/AppDelegate.swift`

- [ ] **Step 1: Add `knowledgeBase` property**

In `class AppDelegate`, after `var hotkeyManager: HotkeyManager?`, add:

```swift
var knowledgeBase: KnowledgeBase?
```

- [ ] **Step 2: Instantiate KnowledgeBase in `setupComponents()`**

After `ollamaClient = OllamaClient()` and `ollamaClient?.warmup()`, add:

```swift
knowledgeBase = KnowledgeBase(ollama: ollamaClient!)
```

- [ ] **Step 3: Update `onBlockClicked` callback**

Replace the existing `floatingPanel?.onBlockClicked` block:

```swift
// Block click → copy to clipboard + retrieve knowledge
floatingPanel?.onBlockClicked = { [weak self] en, zh, metadata in
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("\(en)\n\(zh)", forType: .string)

    guard let self, let kb = self.knowledgeBase, !kb.sections.isEmpty else { return }
    Task {
        if let section = await kb.retrieve(query: en) {
            DispatchQueue.main.async {
                self.floatingPanel?.showKnowledge(title: section.title, body: section.body)
            }
        }
    }
}
```

- [ ] **Step 4: Verify build**

```bash
cd ~/Projects/InterviewCopilot && swift build -c release 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/InterviewCopilot/AppDelegate.swift
git commit -m "feat: wire onBlockClicked to KnowledgeBase retrieval"
```

---

## Task 5: Package and integration test

- [ ] **Step 1: Package**

```bash
cd ~/Projects/InterviewCopilot && make package 2>&1 | tail -5
```

Expected: `==> Done: Phrased.app`

- [ ] **Step 2: Launch**

```bash
open ~/Projects/InterviewCopilot/Phrased.app
```

- [ ] **Step 3: Verify — subtitle mode still works**

Play a YouTube English video. Click ▶ 开始. Confirm subtitles appear with EN + ZH as before.

- [ ] **Step 4: Verify — knowledge panel expands on click**

Click a finalized (greyed-out) subtitle block. Panel should:
- Animate from 440px to 900px
- Show subtitle on left 1/3
- Show section title + body on right 2/3
- Show ✕ button top-right of knowledge area

- [ ] **Step 5: Verify — close button works**

Click ✕. Panel should animate back to 440px.

- [ ] **Step 6: Verify — clicking different blocks updates content**

With panel expanded, click another block. Right panel content should update without re-animating width.

- [ ] **Step 7: Push**

```bash
cd ~/Projects/InterviewCopilot && git push
```

---

## Error handling (already baked in)

- Ollama unavailable: `complete()` returns `""`, `parseIndex` falls back to section 0 → shows first section
- No sections loaded: `kb.sections.isEmpty` guard in AppDelegate prevents any retrieval call
- Panel never collapses unless ✕ clicked — content stays visible for user to read
