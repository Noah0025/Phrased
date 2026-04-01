# Knowledge Copilot Feature — Design Spec

**Date:** 2026-04-01
**Status:** Approved

---

## Overview

Add a click-to-retrieve knowledge base panel to Murmur. When the user clicks a finalized subtitle block, the app retrieves the most relevant section from a pre-prepared Markdown knowledge base and displays it in an expanded right panel. Intended for interview use: click a heard question → instantly see prepared talking points.

---

## Architecture

### New component: `KnowledgeBase.swift`

Responsible for:
1. **Loading** — reads `interview_context.txt` at startup, parses into sections
2. **Retrieval** — given a query string, uses Ollama to identify the most relevant section, returns its content

**Parsing:** Split by `##` headers. Each section = `{ title: String, body: String }`. `#` top-level heading is metadata/context (not a retrievable section).

**Retrieval prompt:**
```
You are helping find relevant interview prep material.
Question/statement heard: "{query}"

Available sections (by number):
1. {title1}
2. {title2}
...

Reply with ONLY the number of the most relevant section.
```
Single non-streaming completion call. Parse the number from response, return the corresponding section body. Fallback to section 1 if parse fails.

### Modified: `OllamaClient.swift`

Add `complete(prompt:) async -> String` — non-streaming single completion for retrieval.

### Modified: `FloatingPanel.swift`

**Panel states:**
- **Collapsed** (default): 440px wide, subtitle area fills full width
- **Expanded**: 900px wide, split into left 1/3 (~290px) and right 2/3 (~590px)

**Right panel contents:**
- Section title (bold, top)
- Section body (scrollable NSTextView, selectable, non-editable)
- `×` close button (top-right of right panel) → collapses back to 440px

**Expansion behavior:**
- First block click triggers expansion (animated `setFrame`)
- Subsequent clicks update content without re-animating width
- `×` closes the right panel and snaps back to 440px

**Public API additions:**
```swift
func showKnowledge(title: String, body: String)
func hideKnowledge()
```

### Modified: `AppDelegate.swift`

Wire `onBlockClicked`:
1. Existing clipboard copy stays
2. Call `knowledgeBase.retrieve(query: en)` async
3. On result → `floatingPanel?.showKnowledge(title:body:)`

---

## Data Flow

```
User clicks block
       ↓
AppDelegate.onBlockClicked(en, zh, metadata)
       ↓
KnowledgeBase.retrieve(query: en)       ← async, ~1-2s
       ↓
OllamaClient.complete(prompt)           ← non-streaming
       ↓
Parse section index → return section
       ↓
FloatingPanel.showKnowledge(title, body)
       ↓
Panel expands (if collapsed) + content displayed
```

---

## Knowledge Base Format

`Sources/InterviewCopilot/Resources/interview_context.txt` — Markdown:

```markdown
# Context heading (not retrieved)

## Section Title
Body content for this section.
Multi-paragraph is fine.

## Another Section
...
```

The current file already has usable content. No format migration needed beyond confirming `##` headers are used (they are).

---

## Error Handling

- Ollama unavailable / timeout: show "Knowledge base unavailable" placeholder in right panel
- No sections parsed: log warning, feature silently disabled
- Parse failure on index: fall back to section 1

---

## What's NOT in scope

- Embedding-based semantic search (can be added later)
- Multiple knowledge base files
- Editing knowledge base from within the app
- Answer generation from knowledge base (that's `AnswerFeature`)
