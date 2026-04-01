# Copilot Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the user clicks a finalized subtitle block, the floating panel expands to 1320px and the right 2/3 streams knowledge-base results from Ollama.

**Architecture:** Block click triggers `CopilotFeature.query(en)` → `OllamaClient.searchKnowledgeBase()` streams chunks → `FloatingPanel` shows `CopilotPanel` on the right. Panel expands/collapses with a close button.

**Tech Stack:** Swift 5.9, AppKit (NSPanel, NSTextView, NSScrollView), Ollama HTTP API (streaming), SPM

---

## File Map

| Action | File | Change |
|--------|------|--------|
| Modify | `Sources/InterviewCopilot/OllamaClient.swift` | Add `searchKnowledgeBase(query:context:onChunk:onComplete:)` |
| Create | `Sources/InterviewCopilot/CopilotFeature.swift` | New class: loads context, drives query, cancels in-progress task |
| Modify | `Sources/InterviewCopilot/FloatingPanel.swift` | Add `CopilotPanel` inner class + `showCopilot/hideCopilot/streamCopilotChunk/clearCopilot` |
| Modify | `Sources/InterviewCopilot/AppDelegate.swift` | Add `copilotFeature`, wire `onBlockClicked` to it |

---

## Task 1: Add `searchKnowledgeBase` to OllamaClient

**Files:**
- Modify: `Sources/InterviewCopilot/OllamaClient.swift`

- [ ] **Step 1: Add the method after `suggestAnswer`**

Open `OllamaClient.swift`. After the closing brace of `suggestAnswer` (around line 72), add:

```swift
// MARK: - Feature 3: Knowledge base retrieval (streaming)
func searchKnowledgeBase(
    query: String,
    context: String,
    onChunk: @escaping (String) -> Void,
    onComplete: @escaping () -> Void
) {
    let systemPrompt = """
    You are a knowledge retrieval assistant for an interview.
    Given a sentence the interviewer said, find the most relevant sections
    from the candidate's preparation notes below.
    Return 3-5 concise bullet points in English only.
    Be specific — quote exact facts, numbers, or concepts from the notes.

    === CANDIDATE NOTES ===
    \(context)
    """

    let userPrompt = "Interviewer said: \"\(query)\"\n\nWhat relevant points should the candidate mention?"

    Task {
        await chatStream(model: fastModel, systemPrompt: systemPrompt, userPrompt: userPrompt, onChunk: onChunk, onComplete: onComplete)
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
cd ~/Projects/InterviewCopilot && swift build -c release 2>&1 | grep -E "error:|warning:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/InterviewCopilot && git add Sources/InterviewCopilot/OllamaClient.swift
git commit -m "feat: add searchKnowledgeBase streaming method to OllamaClient"
```

---

## Task 2: Create CopilotFeature

**Files:**
- Create: `Sources/InterviewCopilot/CopilotFeature.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation

class CopilotFeature {
    private let ollama: OllamaClient
    private let panel: FloatingPanel
    private var context: String = ""
    private var activeTask: Task<Void, Never>?

    init(ollama: OllamaClient, panel: FloatingPanel) {
        self.ollama = ollama
        self.panel = panel
        loadContext()
    }

    func query(_ text: String) {
        // Cancel any in-progress query
        activeTask?.cancel()
        activeTask = nil

        panel.clearCopilot()
        panel.showCopilot(query: text)

        let ctx = context
        activeTask = Task {
            ollama.searchKnowledgeBase(
                query: text,
                context: ctx,
                onChunk: { [weak self] chunk in
                    guard !Task.isCancelled else { return }
                    self?.panel.streamCopilotChunk(chunk)
                },
                onComplete: { [weak self] in
                    self?.activeTask = nil
                }
            )
        }
    }

    private func loadContext() {
        if let url = Bundle.main.url(forResource: "interview_context", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            context = content
            return
        }
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let fallback = execDir.appendingPathComponent("interview_context.txt")
        if let content = try? String(contentsOf: fallback, encoding: .utf8) {
            context = content
            return
        }
        context = "No context loaded."
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd ~/Projects/InterviewCopilot && swift build -c release 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

Note: Will get errors about `clearCopilot`, `showCopilot`, `streamCopilotChunk` not defined on `FloatingPanel` — that's expected, those come in Task 3.

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/InterviewCopilot && git add Sources/InterviewCopilot/CopilotFeature.swift
git commit -m "feat: add CopilotFeature class"
```

---

## Task 3: Add CopilotPanel to FloatingPanel

**Files:**
- Modify: `Sources/InterviewCopilot/FloatingPanel.swift`

This is the largest task. It has two parts:
- Part A: Add the `CopilotPanel` NSView class at the top of the file
- Part B: Add expand/collapse/stream methods to `FloatingPanel`

- [ ] **Step 1: Add `CopilotPanel` class before `// MARK: - Floating Panel`**

Insert the following class right before the line `// MARK: - Floating Panel` (around line 108):

```swift
// MARK: - Copilot Panel

class CopilotPanel: NSView {
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        layer?.cornerRadius = 8

        // Separator on the left edge
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Title
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Close button
        closeButton.bezelStyle = .rounded
        closeButton.font = NSFont.systemFont(ofSize: 11)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        // Text view for streamed content
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .labelColor

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        [separator, titleLabel, closeButton, scrollView].forEach { addSubview($0) }

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),

            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func closeTapped() {
        onClose?()
    }

    func setQuery(_ text: String) {
        titleLabel.stringValue = text
        textView.string = ""
    }

    func appendChunk(_ chunk: String) {
        DispatchQueue.main.async {
            let clean = chunk.replacingOccurrences(of: "\n", with: "\n")
            self.textView.string += clean
            // Scroll to bottom
            let range = NSRange(location: self.textView.string.count, length: 0)
            self.textView.scrollRangeToVisible(range)
        }
    }

    func clear() {
        textView.string = ""
        titleLabel.stringValue = ""
    }
}
```

- [ ] **Step 2: Add properties and constants to `FloatingPanel`**

In `FloatingPanel`, add these new stored properties right after `private var bottomBar: NSView!` (around line 127):

```swift
private var copilotPanel: CopilotPanel?
private let copilotWidth: CGFloat = 880
private var isCopilotVisible = false
```

- [ ] **Step 3: Add public methods to `FloatingPanel`**

At the end of `FloatingPanel`, just before the final closing `}` (the one that closes the class), replace the existing stubs:

```swift
// The stubs at lines ~521-523 currently read:
//   func appendAnswerChunk(_ chunk: String) {}
//   func clearAnswer() {}
//   func setAnswerLoading(_ loading: Bool) {}
// Replace them entirely with:
```

Remove the three stub lines and insert:

```swift
// MARK: - Copilot

func showCopilot(query: String) {
    DispatchQueue.main.async {
        guard !self.isCopilotVisible else {
            self.copilotPanel?.setQuery(query)
            return
        }
        self.isCopilotVisible = true

        // Create panel if needed
        if self.copilotPanel == nil {
            let cp = CopilotPanel()
            cp.translatesAutoresizingMaskIntoConstraints = false
            cp.onClose = { [weak self] in self?.hideCopilot() }
            self.contentView?.addSubview(cp)
            self.copilotPanel = cp
            // Pin to right side, same height as content area
            NSLayoutConstraint.activate([
                cp.topAnchor.constraint(equalTo: self.contentView!.topAnchor),
                cp.bottomAnchor.constraint(equalTo: self.contentView!.bottomAnchor),
                cp.leadingAnchor.constraint(equalTo: self.contentView!.leadingAnchor,
                                             constant: self.panelWidth),
                cp.trailingAnchor.constraint(equalTo: self.contentView!.trailingAnchor),
            ])
        }
        self.copilotPanel?.setQuery(query)

        // Expand panel width
        var f = self.frame
        f.size.width = self.panelWidth + self.copilotWidth
        self.setFrame(f, display: true, animate: true)
    }
}

func hideCopilot() {
    DispatchQueue.main.async {
        guard self.isCopilotVisible else { return }
        self.isCopilotVisible = false
        var f = self.frame
        f.size.width = self.panelWidth
        self.setFrame(f, display: true, animate: true)
    }
}

func streamCopilotChunk(_ chunk: String) {
    copilotPanel?.appendChunk(chunk)
}

func clearCopilot() {
    DispatchQueue.main.async {
        self.copilotPanel?.clear()
    }
}
```

- [ ] **Step 4: Build**

```bash
cd ~/Projects/InterviewCopilot && swift build -c release 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

Fix any compile errors before proceeding.

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/InterviewCopilot && git add Sources/InterviewCopilot/FloatingPanel.swift
git commit -m "feat: add CopilotPanel and expand/collapse logic to FloatingPanel"
```

---

## Task 4: Wire CopilotFeature in AppDelegate

**Files:**
- Modify: `Sources/InterviewCopilot/AppDelegate.swift`

- [ ] **Step 1: Add `copilotFeature` property**

After `var answerFeature: AnswerFeature?` (line 11), add:

```swift
var copilotFeature: CopilotFeature?
```

- [ ] **Step 2: Initialize `copilotFeature` in `setupComponents()`**

After the `answerFeature = AnswerFeature(...)` block (around line 46), add:

```swift
copilotFeature = CopilotFeature(
    ollama: ollamaClient!,
    panel: floatingPanel!
)
```

- [ ] **Step 3: Replace the `onBlockClicked` handler**

Find this block (around line 71):

```swift
// Block click → copy to clipboard
floatingPanel?.onBlockClicked = { en, zh, metadata in
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("\(en)\n\(zh)", forType: .string)
}
```

Replace with:

```swift
// Block click → Copilot knowledge base lookup
floatingPanel?.onBlockClicked = { [weak self] en, zh, metadata in
    self?.copilotFeature?.query(en)
}
```

- [ ] **Step 4: Build**

```bash
cd ~/Projects/InterviewCopilot && swift build -c release 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/InterviewCopilot && git add Sources/InterviewCopilot/AppDelegate.swift
git commit -m "feat: wire CopilotFeature to block click in AppDelegate"
```

---

## Task 5: Package, Launch and Smoke Test

**Files:** None — build and run only

- [ ] **Step 1: Package**

```bash
cd ~/Projects/InterviewCopilot && make package 2>&1
```
Expected: `==> Done: Murmur.app`

- [ ] **Step 2: Launch**

```bash
open ~/Projects/InterviewCopilot/Murmur.app
```

- [ ] **Step 3: Smoke test — copilot panel**

Use test mode to verify without needing audio:

```bash
open ~/Projects/InterviewCopilot/Murmur.app --args --test
```

In the test input box, type a sentence and press Enter (onFinal). This creates a finalized block. Click the block.

**Expected:**
- Panel expands to ~1320px wide
- Right side shows the EN sentence as title
- Ollama streams bullet points relevant to the query
- Clicking ✕ collapses the panel back to 440px

- [ ] **Step 4: Commit if all OK**

```bash
cd ~/Projects/InterviewCopilot && git add -A && git status
# Should show nothing to commit if previous tasks committed properly
git log --oneline -5
```
