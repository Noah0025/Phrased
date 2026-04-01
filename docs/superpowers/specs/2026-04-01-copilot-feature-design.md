# Copilot Feature Design — Murmur

**Date:** 2026-04-01
**Status:** Approved

## Overview

When the user clicks a finalized subtitle block, the floating panel expands to show knowledge base results on the right. The left 1/3 remains unchanged (real-time subtitles); the right 2/3 streams relevant content from `interview_context.txt` via Ollama.

## Architecture

### New: `CopilotFeature.swift`
- Loads `interview_context.txt` (same loading logic as `AnswerFeature`)
- `query(text: String)`: cancels any in-progress Task, starts a new streaming query
- Prompt: retrieval-style — find relevant sections from knowledge base, return as bullet points
- Uses `OllamaClient` streaming (reuses `chatStream`)

### New: `CopilotPanel` (in `FloatingPanel.swift`)
- NSView added to the right side of the expanded panel
- NSScrollView + NSTextView for streamed output
- Title label showing the queried sentence
- Close (✕) button calls `hideCopilot()`

### Modified: `FloatingPanel`
- `panelWidth` stays at 440px (subtitle side)
- `copilotWidth`: 880px (2/3)
- `showCopilot(query:)`: expands panel to 1320px, makes CopilotPanel visible
- `hideCopilot()`: collapses back to 440px
- `streamCopilotChunk(_ chunk: String)`: appends to CopilotPanel's text view
- `clearCopilot()`: clears text, resets title

### Modified: `OllamaClient`
- Add `searchKnowledgeBase(query:context:onChunk:onComplete:)` method

### Modified: `AppDelegate`
- `onBlockClicked` now triggers `copilotFeature?.query(en)` instead of clipboard copy

## Data Flow

```
User clicks block → FloatingPanel.onBlockClicked(en, zh)
  → CopilotFeature.query(en)
    → cancel previous Task
    → OllamaClient.searchKnowledgeBase(en, context)
      → streaming chunks → FloatingPanel.streamCopilotChunk()
        → CopilotPanel NSTextView updates in real-time
User clicks ✕ → FloatingPanel.hideCopilot()
  → panel collapses 1320 → 440px
```

## Layout

- Collapsed: 440px wide (current)
- Expanded: 1320px (440 left + 880 right)
- Panel height unchanged
- Left scrollView stays pinned to left 440px
- CopilotPanel occupies right 880px, same height as content area

## Prompt Design

```
System: You are a knowledge retrieval assistant for an interview.
Given a sentence, find the most relevant sections from the context below.
Return 3-5 concise bullet points in English.

=== CONTEXT ===
{interview_context}

User: "{en_text}"
```

## What Is Not Changed

- `SubtitleFeature`, `SpeechTranscriber`, `AudioCapture`, `HotkeyManager` — untouched
- Left subtitle scroll area — layout unchanged, only width constraint adjusted when panel expands
