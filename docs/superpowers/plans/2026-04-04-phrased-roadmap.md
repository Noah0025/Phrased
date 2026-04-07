# Phrased Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Phrased from a fixed-style, Ollama-only input enhancer into a fully configurable, context-aware text assistant with pluggable ASR/LLM providers, selectable audio source (mic or system audio), user-defined templates, direct text injection, history, and vocabulary expansion.

**Architecture:** Phase 0 fixes existing bugs before any new feature work. Phases 1–2 are infrastructure (providers + settings + audio source) that everything else depends on. Phases 3–7 build features on top. The Settings window grows incrementally each phase.

**Tech Stack:** Swift 5.9+, SPM, AppKit, SwiftUI, Combine, Carbon (hotkey), AVAudioEngine (microphone), ScreenCaptureKit (system audio), AXUIElement (Accessibility API), NSPasteboard, XCTest

---

## File Structure

```
Sources/Phrased/
├── App/
│   ├── AppDelegate.swift                [modify] wire providers, settings, history
│   ├── StatusBarController.swift        [modify] add menu: Settings, History, Quit
│   └── main.swift                       [no change]
│
├── Core/
│   ├── Providers/
│   │   ├── LLMProvider.swift            [create] protocol + LLMMessage type
│   │   ├── ASRProvider.swift            [create] protocol (onPartial + onFinal)
│   │   ├── OllamaLLMProvider.swift      [create] wraps OllamaClient
│   │   └── OpenAICompatibleProvider.swift [create] OpenAI-compatible HTTP LLM
│   ├── IntentProcessor.swift            [modify] use LLMProvider + PromptTemplate
│   ├── OllamaClient.swift               [keep, internal to OllamaLLMProvider]
│   ├── PromptTemplate.swift             [create] user-defined template struct
│   └── UserProfile.swift                [delete — always empty, never written, dead code]
│
├── Settings/
│   ├── PhrasedSettings.swift             [create] Codable, all user prefs
│   ├── SettingsWindowController.swift   [create] NSWindowController wrapper
│   └── SettingsView.swift               [create] SwiftUI TabView UI
│
├── Input/
│   ├── InputWindow.swift                [modify] use ASRProvider, audio source toggle
│   ├── HotkeyManager.swift              [modify] load hotkey from PhrasedSettings
│   ├── AudioCapture.swift               [rename → SystemAudioCapture.swift] system audio via SCK
│   ├── MicrophoneCapture.swift          [create] mic input via AVAudioEngine
│   ├── SpeechTranscriber.swift          [delete — dead code, never used]
│   └── WhisperTranscriber.swift         [modify] fix blocking waitUntilExit, add onPartial stub
│
├── Context/
│   └── ContextCapture.swift             [create] selected text, clipboard, frontmost app
│
├── Confirm/
│   ├── ConfirmViewModel.swift           [modify] use LLMProvider, context, injection
│   └── ConfirmWindow.swift             [modify] template picker, inject button, source badge
│
├── Output/
│   ├── ClipboardOutput.swift            [no change]
│   └── TextInjector.swift               [create] clipboard swap + ⌘V simulation
│
├── History/
│   ├── HistoryStore.swift               [create] JSON append-log, max 500 entries
│   └── HistoryWindowController.swift    [create] floating list window
│
└── Vocabulary/
    └── VocabularyStore.swift            [create] trigger→expansion pairs, whole-word regex

Tests/PhrasedTests/
├── LLMProviderTests.swift
├── ASRProviderTests.swift
├── PromptTemplateTests.swift
├── PhrasedSettingsTests.swift
├── ContextCaptureTests.swift
├── HistoryStoreTests.swift
└── VocabularyStoreTests.swift
```

---

## Phase 0: Bug Fixes & Dead Code Cleanup

**必须先做，再动任何新功能。**

### Task 0.1: 修复 `isLocked` 跨 session 不重置

**Files:**
- Modify: `Sources/Phrased/Confirm/ConfirmWindow.swift`

- [ ] **Step 1: 在 `onDismiss` 和 `windowDidResignKey` 里补充重置**

在 `PhrasedWindowController.init()` 的 `onDismiss` 闭包里：
```swift
confirmVM.onDismiss = { [weak self] in
    self?.window?.orderOut(nil)
    confirmVM.streamedResult = ""
    confirmVM.showFeedbackField = false
    confirmVM.isLocked = false   // ← 新增
}
```

在 `windowDidResignKey` 里：
```swift
func windowDidResignKey(_ notification: Notification) {
    guard !isBeingShown, !confirmVM.isLocked else { return }
    window?.orderOut(nil)
    confirmVM.streamedResult = ""
    confirmVM.showFeedbackField = false
    confirmVM.isLocked = false   // ← 新增
}
```

- [ ] **Step 2: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Phrased/Confirm/ConfirmWindow.swift
git commit -m "fix: reset isLocked on dismiss so next session starts unlocked"
```

---

### Task 0.2: 删除死代码

**Files:**
- Delete: `Sources/Phrased/Input/SpeechTranscriber.swift`
- Modify: `Sources/Phrased/Confirm/ConfirmViewModel.swift`
- Modify: `Sources/Phrased/Core/IntentProcessor.swift`
- Delete: `Sources/Phrased/Core/UserProfile.swift`

- [ ] **Step 1: 删除 SpeechTranscriber**

```bash
rm Sources/Phrased/Input/SpeechTranscriber.swift
```

- [ ] **Step 2: 删除 UserProfile**

`IntentProcessor` 依赖 `UserProfile`，先清理 IntentProcessor：

从 `IntentProcessor.swift` 中删除 `UserProfile` 相关内容。保留 `buildMessages()` 函数，但去掉 `profile` 属性、`updateProfile()`、`profileDescription()`，以及 system message 逻辑（该逻辑永远不执行）：

```swift
// Sources/Phrased/Core/IntentProcessor.swift
import Foundation

class IntentProcessor {
    func buildMessages(input: String, feedback: String?, style: WritingStyle = .auto) -> [OllamaMessage] {
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

        return [OllamaMessage(role: "user", content: userContent)]
    }
}
```

```bash
rm Sources/Phrased/Core/UserProfile.swift
```

- [ ] **Step 3: 删除 ConfirmViewModel 里的 `continueWithNewInput`**

从 `ConfirmViewModel.swift` 中删除：
```swift
// 删除整个方法：
func continueWithNewInput(_ input: String, style: WritingStyle = .auto) { ... }
```

- [ ] **Step 4: 删除 InputViewModel 里的 `partialTranscript`**

从 `InputWindow.swift` 中删除：
```swift
// 删除：
@Published var partialTranscript: String = ""
```

- [ ] **Step 5: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: remove dead code — SpeechTranscriber, UserProfile, continueWithNewInput, partialTranscript"
```

---

### Task 0.3: 修复 `WhisperTranscriber` 阻塞协程线程

**Files:**
- Modify: `Sources/Phrased/Input/WhisperTranscriber.swift`

问题：`process.waitUntilExit()` 是同步阻塞调用，在 `Task { await transcribe(...) }` 内部会占住 Swift 协程池线程。

- [ ] **Step 1: 用 `terminationHandler` + `withCheckedContinuation` 替换**

将 `transcribe()` 里的阻塞部分改为非阻塞：

```swift
private func transcribe(fileURL: URL) async {
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let txtURL = fileURL.deletingPathExtension().appendingPathExtension("txt")
    defer { try? FileManager.default.removeItem(at: txtURL) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: Self.whisperPath)
    process.arguments = [
        fileURL.path,
        "--model", "mlx-community/whisper-small-mlx",
        "--output-format", "txt",
        "--output-dir", fileURL.deletingLastPathComponent().path,
    ]
    process.environment = [
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
        "HOME": NSHomeDirectory(),
    ]
    process.standardOutput = Pipe()
    process.standardError = Pipe()

    do {
        try process.run()
    } catch {
        DispatchQueue.main.async { self.onFinal?("") }
        return
    }

    // Non-blocking wait using continuation
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        process.terminationHandler = { _ in continuation.resume() }
    }

    let text = (try? String(contentsOf: txtURL, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    DispatchQueue.main.async { self.onFinal?(text) }
}
```

`warmUp()` 里同样的 `waitUntilExit()` 改法一致（warmUp 是 background Task，影响小，但统一修改更好）：

```swift
func warmUp() {
    Task.detached(priority: .background) {
        // ... 同样替换 waitUntilExit 为 terminationHandler continuation
        let process = Process()
        // ... 设置 process ...
        try? process.run()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in c.resume() }
        }
        try? FileManager.default.removeItem(at: url)
        let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
        try? FileManager.default.removeItem(at: txtURL)
    }
}
```

- [ ] **Step 2: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Phrased/Input/WhisperTranscriber.swift
git commit -m "fix: replace blocking waitUntilExit with terminationHandler continuation in WhisperTranscriber"
```

---

### Task 0.4: 修复 `AudioCapture` 竞态条件

**Files:**
- Modify: `Sources/Phrased/Input/AudioCapture.swift`

问题：`stop()` 在 `startCapture()` Task 完成前调用时，`stream` 为 nil，stop 无效；之后 startCapture 完成，stream 被赋值但再也不会被 stop。

- [ ] **Step 1: 用 actor 或 flag 防止竞态**

在 `AudioCapture` 里加一个 `isStopped` flag，在 `startCapture()` 内部检查：

```swift
func stop() {
    lock.withLock {
        _isRunning = false
        _isStopped = true   // ← 新增
    }
    Task {
        try? await stream?.stopCapture()
        stream = nil
    }
}

private var _isStopped = false

private func startCapture() async {
    // ... 所有异步操作前检查
    guard !lock.withLock({ _isStopped }) else { return }
    do {
        // ... 同原来一样 ...
        let newStream = SCStream(...)
        try await newStream.startCapture()
        // 启动后再次检查，如果已 stop 则立即停止
        guard !lock.withLock({ _isStopped }) else {
            try? await newStream.stopCapture()
            return
        }
        self.stream = newStream
        lock.withLock { self._isRunning = true }
    } catch {}
}
```

同时在 `start()` 里重置 flag：
```swift
func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
    lock.withLock { _isStopped = false }
    self.onBuffer = onBuffer
    Task { await startCapture() }
}
```

- [ ] **Step 2: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Phrased/Input/AudioCapture.swift
git commit -m "fix: prevent SCStream leak when stop() races with startCapture() async task"
```

---

## Phase 1: Provider Protocol Abstraction

### Task 1.1: LLMProvider Protocol

**Files:**
- Create: `Sources/Phrased/Core/Providers/LLMProvider.swift`
- Create: `Tests/PhrasedTests/LLMProviderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PhrasedTests/LLMProviderTests.swift
import XCTest
@testable import Phrased

final class LLMProviderTests: XCTestCase {
    func test_mockProvider_streamsChunks() async {
        let mock = MockLLMProvider(response: "hello world")
        var collected = ""
        let task = mock.streamChat(
            messages: [LLMMessage(role: "user", content: "hi")],
            onChunk: { collected += $0 },
            onDone: {}
        )
        await task.value
        XCTAssertEqual(collected, "hello world")
    }
}

class MockLLMProvider: LLMProvider {
    let response: String
    init(response: String) { self.response = response }

    func streamChat(
        messages: [LLMMessage],
        onChunk: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task {
            await onChunk(response)
            await onDone()
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LLMProviderTests 2>&1 | tail -10`
Expected: FAIL — `LLMProvider`, `LLMMessage` not defined

- [ ] **Step 3: Create the protocol**

```swift
// Sources/Phrased/Core/Providers/LLMProvider.swift
import Foundation

struct LLMMessage {
    let role: String
    let content: String
}

protocol LLMProvider {
    @discardableResult
    func streamChat(
        messages: [LLMMessage],
        onChunk: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LLMProviderTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Phrased/Core/Providers/LLMProvider.swift Tests/PhrasedTests/LLMProviderTests.swift
git commit -m "feat: LLMProvider protocol with LLMMessage"
```

---

### Task 1.2: OllamaLLMProvider + OpenAICompatibleProvider

**Files:**
- Create: `Sources/Phrased/Core/Providers/OllamaLLMProvider.swift`
- Create: `Sources/Phrased/Core/Providers/OpenAICompatibleProvider.swift`
- Modify: `Tests/PhrasedTests/LLMProviderTests.swift`

- [ ] **Step 1: Add conformance tests**

```swift
// 追加到 LLMProviderTests.swift:
func test_ollamaProvider_conformsToProtocol() {
    let provider: LLMProvider = OllamaLLMProvider(model: "qwen2.5:7b")
    XCTAssertNotNil(provider)
}

func test_openAIProvider_conformsToProtocol() {
    let provider: LLMProvider = OpenAICompatibleProvider(
        baseURL: "https://api.openai.com", apiKey: "sk-test", model: "gpt-4o-mini"
    )
    XCTAssertNotNil(provider)
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter LLMProviderTests`
Expected: FAIL

- [ ] **Step 3: Create OllamaLLMProvider**

```swift
// Sources/Phrased/Core/Providers/OllamaLLMProvider.swift
import Foundation

class OllamaLLMProvider: LLMProvider {
    private let client: OllamaClient

    init(model: String = "qwen2.5:7b") {
        self.client = OllamaClient(model: model)
    }

    func streamChat(
        messages: [LLMMessage],
        onChunk: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        let ollamaMessages = messages.map { OllamaMessage(role: $0.role, content: $0.content) }
        return client.streamChat(messages: ollamaMessages, onChunk: onChunk, onDone: onDone)
    }
}
```

- [ ] **Step 4: Create OpenAICompatibleProvider**

```swift
// Sources/Phrased/Core/Providers/OpenAICompatibleProvider.swift
import Foundation

/// Supports OpenAI, Groq, Moonshot, DeepSeek, llama.cpp, etc.
class OpenAICompatibleProvider: LLMProvider {
    private let baseURL: String
    private let apiKey: String
    private let model: String

    init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.model = model
    }

    func streamChat(
        messages: [LLMMessage],
        onChunk: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task {
            guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
                await onDone(); return
            }
            let body: [String: Any] = [
                "model": model,
                "messages": messages.map { ["role": $0.role, "content": $0.content] },
                "stream": true
            ]
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            guard let (bytes, _) = try? await URLSession.shared.bytes(for: request) else {
                await onDone(); return
            }
            do {
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let content = delta["content"] as? String,
                          !content.isEmpty else { continue }
                    await onChunk(content)
                }
            } catch {}
            await onDone()
        }
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter LLMProviderTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/Phrased/Core/Providers/OllamaLLMProvider.swift \
        Sources/Phrased/Core/Providers/OpenAICompatibleProvider.swift \
        Tests/PhrasedTests/LLMProviderTests.swift
git commit -m "feat: OllamaLLMProvider and OpenAICompatibleProvider"
```

---

### Task 1.3: ASRProvider Protocol

**Files:**
- Create: `Sources/Phrased/Core/Providers/ASRProvider.swift`
- Modify: `Sources/Phrased/Input/WhisperTranscriber.swift`
- Create: `Tests/PhrasedTests/ASRProviderTests.swift`

`onPartial` 和 `onFinal` 语义说明：
- `onPartial(String)` — 识别中间结果，可多次触发，用于实时字幕显示
- `onFinal(String)` — session 结束时触发**一次**，带完整识别结果，用于提交

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PhrasedTests/ASRProviderTests.swift
import XCTest
import AVFoundation
@testable import Phrased

final class ASRProviderTests: XCTestCase {
    func test_mockASRProvider_conformsToProtocol() {
        let provider: ASRProvider = MockASRProvider()
        XCTAssertNotNil(provider)
    }

    func test_whisperTranscriber_conformsToProtocol() {
        let provider: ASRProvider = WhisperTranscriber()
        XCTAssertNotNil(provider)
    }
}

class MockASRProvider: ASRProvider {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    func warmUp() {}
    func startSession() {}
    func stopSession() {}
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {}
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter ASRProviderTests`
Expected: FAIL

- [ ] **Step 3: Create ASRProvider protocol**

```swift
// Sources/Phrased/Core/Providers/ASRProvider.swift
import AVFoundation

protocol ASRProvider: AnyObject {
    /// Called with intermediate results during recognition (may fire many times).
    var onPartial: ((String) -> Void)? { get set }
    /// Called exactly once when the session ends, with the final complete transcript.
    var onFinal: ((String) -> Void)? { get set }
    func warmUp()
    func startSession()
    func stopSession()
    func appendBuffer(_ buffer: AVAudioPCMBuffer)
}
```

- [ ] **Step 4: Make WhisperTranscriber conform**

Append to `WhisperTranscriber.swift`:
```swift
// WhisperTranscriber already has onFinal: ((String) -> Void)?
// Add onPartial (stub — Whisper has no streaming partial results):
// In the class body, add:
var onPartial: ((String) -> Void)? = nil

extension WhisperTranscriber: ASRProvider {}
```

- [ ] **Step 5: Migrate ConfirmViewModel and InputViewModel to use protocols**

In `ConfirmViewModel.swift`, change:
```swift
// Before:
private let ollama: OllamaClient
init(ollama: OllamaClient, processor: IntentProcessor) { self.ollama = ollama

// After:
private var llm: LLMProvider
init(llm: LLMProvider, processor: IntentProcessor) { self.llm = llm
```

Replace `ollama.streamChat(messages:...)` → `llm.streamChat(messages:...)`.

Update `IntentProcessor.buildMessages()` return type from `[OllamaMessage]` to `[LLMMessage]` (replace `OllamaMessage(` with `LLMMessage(`).

Add `updateProvider` to `ConfirmViewModel`:
```swift
func updateProvider(_ provider: LLMProvider) {
    streamTask?.cancel()
    self.llm = provider
}
```

In `InputWindow.swift` `InputViewModel`, change:
```swift
// Before:
private let transcriber = WhisperTranscriber()

// After:
private var transcriber: ASRProvider = WhisperTranscriber()

func updateASRProvider(_ provider: ASRProvider) {
    provider.onFinal = transcriber.onFinal  // transfer callback
    self.transcriber = provider
}
```

In `AppDelegate.swift`:
```swift
private lazy var llmProvider: LLMProvider = OllamaLLMProvider(model: "qwen2.5:7b")
private lazy var confirmVM = ConfirmViewModel(llm: llmProvider, processor: processor)
```

- [ ] **Step 6: Build to confirm no errors**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add Sources/Phrased/Core/Providers/ASRProvider.swift \
        Sources/Phrased/Input/WhisperTranscriber.swift \
        Sources/Phrased/Core/IntentProcessor.swift \
        Sources/Phrased/Confirm/ConfirmViewModel.swift \
        Sources/Phrased/Input/InputWindow.swift \
        Sources/Phrased/App/AppDelegate.swift \
        Tests/PhrasedTests/ASRProviderTests.swift
git commit -m "feat: ASRProvider protocol, migrate to LLMProvider+ASRProvider throughout"
```

---

## Phase 2: Settings + Audio Source Selection

### Task 2.1: MicrophoneCapture

**Files:**
- Create: `Sources/Phrased/Input/MicrophoneCapture.swift`
- Rename: `AudioCapture.swift` → `SystemAudioCapture.swift` (class name stays `AudioCapture` for now, rename optional)

- [ ] **Step 1: Create MicrophoneCapture**

```swift
// Sources/Phrased/Input/MicrophoneCapture.swift
import AVFoundation

/// Captures microphone input via AVAudioEngine.
/// Calls onBuffer with 16kHz mono Float32 PCM buffers — same format as SystemAudioCapture.
class MicrophoneCapture {
    private var engine: AVAudioEngine?
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private(set) var isRunning = false

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // Install tap at native format, then convert to 16kHz mono
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converted = self.convert(buffer, to: self.targetFormat) else { return }
            self.onBuffer?(converted)
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            consumed = true
            return buffer
        }
        return error == nil ? out : nil
    }
}
```

- [ ] **Step 2: Build to confirm no errors**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Phrased/Input/MicrophoneCapture.swift
git commit -m "feat: MicrophoneCapture via AVAudioEngine, outputs 16kHz mono PCM"
```

---

### Task 2.2: PhrasedSettings Model

**Files:**
- Create: `Sources/Phrased/Settings/PhrasedSettings.swift`
- Create: `Tests/PhrasedTests/PhrasedSettingsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PhrasedTests/PhrasedSettingsTests.swift
import XCTest
@testable import Phrased

final class PhrasedSettingsTests: XCTestCase {
    var tmpURL: URL!

    override func setUp() {
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmpURL) }

    func test_defaultSettings_roundTrip() throws {
        let s = PhrasedSettings()
        try s.save(to: tmpURL)
        let loaded = try PhrasedSettings.load(from: tmpURL)
        XCTAssertEqual(loaded.llmProviderID, s.llmProviderID)
        XCTAssertEqual(loaded.hotkeyKeyCode, s.hotkeyKeyCode)
        XCTAssertEqual(loaded.audioSource, s.audioSource)
    }

    func test_modifiedSettings_persist() throws {
        var s = PhrasedSettings()
        s.llmProviderID = "openai"
        s.audioSource = "microphone"
        s.hotkeyKeyCode = 36
        try s.save(to: tmpURL)
        let loaded = try PhrasedSettings.load(from: tmpURL)
        XCTAssertEqual(loaded.llmProviderID, "openai")
        XCTAssertEqual(loaded.audioSource, "microphone")
        XCTAssertEqual(loaded.hotkeyKeyCode, 36)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter PhrasedSettingsTests`
Expected: FAIL

- [ ] **Step 3: Create PhrasedSettings**

```swift
// Sources/Phrased/Settings/PhrasedSettings.swift
import Foundation

struct PhrasedSettings: Codable {
    // LLM
    var llmProviderID: String = "ollama"        // "ollama" | "openai"
    var ollamaModel: String = "qwen2.5:7b"
    var openAIBaseURL: String = "https://api.openai.com"
    var openAIAPIKey: String = ""
    var openAIModel: String = "gpt-4o-mini"

    // ASR
    var asrProviderID: String = "whisper"       // "whisper" (only option for now)

    // Audio source
    var audioSource: String = "systemAudio"    // "systemAudio" | "microphone"

    // Hotkey (default ⌥Space: keyCode=49, modifiers=["option"])
    var hotkeyKeyCode: UInt16 = 49
    var hotkeyModifiers: [String] = ["option"] // "option"|"command"|"control"|"shift"

    // Output
    var defaultOutputMode: String = "copy"     // "copy" | "inject"

    // Templates — added in Phase 3 after PromptTemplate is created
    // var customTemplates: [PromptTemplate] = []

    static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Phrased", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    func save(to url: URL = PhrasedSettings.defaultStorageURL()) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL = PhrasedSettings.defaultStorageURL()) throws -> PhrasedSettings {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PhrasedSettings.self, from: data)
    }

    static func loadOrDefault() -> PhrasedSettings {
        (try? load()) ?? PhrasedSettings()
    }

    var hotkeyNSModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if hotkeyModifiers.contains("option")  { flags.insert(.option) }
        if hotkeyModifiers.contains("command") { flags.insert(.command) }
        if hotkeyModifiers.contains("control") { flags.insert(.control) }
        if hotkeyModifiers.contains("shift")   { flags.insert(.shift) }
        return flags
    }
}
```

> 注意：文件顶部需要 `import AppKit`（与 `import Foundation` 并列）。

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter PhrasedSettingsTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Phrased/Settings/PhrasedSettings.swift Tests/PhrasedTests/PhrasedSettingsTests.swift
git commit -m "feat: PhrasedSettings with LLM, ASR, audio source, hotkey, output prefs"
```

---

### Task 2.3: Wire Audio Source into InputViewModel

**Files:**
- Modify: `Sources/Phrased/Input/InputWindow.swift`

InputViewModel 目前硬编码使用 `AudioCapture`（系统音频）。改为根据设置切换。

- [ ] **Step 1: 修改 InputViewModel 支持两种音频源**

```swift
// In InputViewModel:
enum AudioSourceMode { case systemAudio, microphone }

private let systemAudioCapture = AudioCapture()
private let micCapture = MicrophoneCapture()
@Published var currentAudioSource: AudioSourceMode = .systemAudio

func setAudioSource(_ source: AudioSourceMode) {
    currentAudioSource = source
}

private func startRecording() {
    isRecording = true
    inputText = ""
    transcriber.startSession()
    switch currentAudioSource {
    case .systemAudio:
        systemAudioCapture.start { [weak self] buffer in
            self?.transcriber.appendBuffer(buffer)
        }
    case .microphone:
        micCapture.start { [weak self] buffer in
            self?.transcriber.appendBuffer(buffer)
        }
    }
}

private func stopRecording() {
    isRecording = false
    isTranscribing = true
    switch currentAudioSource {
    case .systemAudio: systemAudioCapture.stop()
    case .microphone:  micCapture.stop()
    }
    transcriber.stopSession()
}
```

- [ ] **Step 2: 在 AppDelegate 里从 settings 初始化音频源**

```swift
// In AppDelegate.applicationDidFinishLaunching:
let source: InputViewModel.AudioSourceMode = settings.audioSource == "microphone" ? .microphone : .systemAudio
inputVM.setAudioSource(source)
```

- [ ] **Step 3: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/Phrased/Input/InputWindow.swift Sources/Phrased/App/AppDelegate.swift
git commit -m "feat: InputViewModel supports systemAudio/microphone source selection"
```

---

### Task 2.4: 音频源快速切换按钮 + 状态显示

**Files:**
- Modify: `Sources/Phrased/Confirm/ConfirmWindow.swift`

在 `inputBar` 里麦克风按钮旁边，根据当前音频源显示不同图标，点击可快速切换。

- [ ] **Step 1: 在 PhrasedView 里加音频源切换按钮**

在 `PhrasedView` 的 `inputBar` 里，`micButton` 后面（或整合进 micButton label）添加：

```swift
// 替换 micButton 的 label，加音频源标识：
private var micButton: some View {
    Button {
        inputVM.toggleRecording()
    } label: {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: inputVM.isRecording
                  ? "stop.fill"
                  : (inputVM.currentAudioSource == .microphone ? "mic.fill" : "speaker.wave.2.fill"))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(inputVM.isRecording ? .red : .secondary)
                .frame(width: 28, height: 28)
            // 小角标：录音中时不显示
            if !inputVM.isRecording {
                Image(systemName: inputVM.currentAudioSource == .microphone ? "mic" : "tv")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary.opacity(0.6))
                    .offset(x: 2, y: 2)
            }
        }
    }
    .buttonStyle(.plain)
    .help(inputVM.isRecording
          ? "停止"
          : (inputVM.currentAudioSource == .microphone ? "录制麦克风 (点击切换)" : "录制系统音频 (点击切换)"))
    .contextMenu {
        Button("麦克风输入") { inputVM.setAudioSource(.microphone) }
        Button("系统音频") { inputVM.setAudioSource(.systemAudio) }
    }
    .onChange(of: inputVM.isRecording) { pulsing = $0 }
}
```

- [ ] **Step 2: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 3: 手动测试**

```bash
make package && open .build/release/Phrased.app
# 右键麦克风按钮 → 切换到 "麦克风输入" → 录音 → 验证图标变化
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Phrased/Confirm/ConfirmWindow.swift Sources/Phrased/Input/InputWindow.swift
git commit -m "feat: audio source toggle button with context menu (mic / system audio)"
```

---

### Task 2.5: Settings Window

**Files:**
- Create: `Sources/Phrased/Settings/SettingsWindowController.swift`
- Create: `Sources/Phrased/Settings/SettingsView.swift`
- Modify: `Sources/Phrased/App/StatusBarController.swift`
- Modify: `Sources/Phrased/App/AppDelegate.swift`
- Modify: `Sources/Phrased/Input/HotkeyManager.swift`

- [ ] **Step 1: 更新 HotkeyManager 支持动态快捷键**

```swift
// Sources/Phrased/Input/HotkeyManager.swift
import AppKit
import Carbon

class HotkeyManager {
    private var monitors: [Any] = []
    private let onActivate: () -> Void
    private var keyCode: UInt16
    private var modifierFlags: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, onActivate: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers
        self.onActivate = onActivate
        register()
    }

    func update(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers
    }

    private func register() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if self?.matches(e) == true { DispatchQueue.main.async { self?.onActivate() } }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard self?.matches(e) == true else { return e }
            DispatchQueue.main.async { self?.onActivate() }
            return nil
        }) { monitors.append(m) }
    }

    private func matches(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifierFlags
            && event.keyCode == keyCode
    }

    deinit { monitors.forEach { NSEvent.removeMonitor($0) } }
}
```

- [ ] **Step 2: 创建 SettingsWindowController**

```swift
// Sources/Phrased/Settings/SettingsWindowController.swift
import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    init(settings: PhrasedSettings, onSave: @escaping (PhrasedSettings) -> Void) {
        let view = SettingsView(settings: settings, onSave: onSave)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Phrased 设置"
        window.contentViewController = hosting
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
}
```

- [ ] **Step 3: 创建 SettingsView**

```swift
// Sources/Phrased/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @State private var draft: PhrasedSettings
    private let onSave: (PhrasedSettings) -> Void

    init(settings: PhrasedSettings, onSave: @escaping (PhrasedSettings) -> Void) {
        _draft = State(initialValue: settings)
        self.onSave = onSave
    }

    var body: some View {
        TabView {
            modelTab.tabItem    { Label("模型",  systemImage: "cpu") }
            audioTab.tabItem    { Label("音频",  systemImage: "waveform") }
            hotkeyTab.tabItem   { Label("快捷键", systemImage: "keyboard") }
            outputTab.tabItem   { Label("输出",  systemImage: "arrow.right.doc.on.clipboard") }
        }
        .padding()
        .frame(width: 500, height: 440)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("保存") { onSave(draft) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .bottom])
        }
    }

    // MARK: Model Tab
    private var modelTab: some View {
        Form {
            Section("LLM 供应商") {
                Picker("供应商", selection: $draft.llmProviderID) {
                    Text("Ollama (本地)").tag("ollama")
                    Text("OpenAI 兼容").tag("openai")
                }
                if draft.llmProviderID == "ollama" {
                    TextField("模型名称", text: $draft.ollamaModel)
                        .help("例：qwen2.5:7b, gemma3:4b, llama3.2")
                } else {
                    TextField("API 地址", text: $draft.openAIBaseURL)
                    SecureField("API Key", text: $draft.openAIAPIKey)
                    TextField("模型名称", text: $draft.openAIModel)
                }
            }
        }.formStyle(.grouped)
    }

    // MARK: Audio Tab
    private var audioTab: some View {
        Form {
            Section("音频输入源") {
                Picker("输入源", selection: $draft.audioSource) {
                    Text("系统音频（会议/视频字幕）").tag("systemAudio")
                    Text("麦克风（语音输入）").tag("microphone")
                }
                Group {
                    if draft.audioSource == "systemAudio" {
                        Text("捕获系统播放的音频。适合：转写 Zoom/Teams 会议、视频字幕。\n需要屏幕录制权限（TCC）。每次重新编译后需重新授权。")
                    } else {
                        Text("通过麦克风录制你的声音。适合：语音转文字输入。\n需要麦克风权限。")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Section("语音识别引擎") {
                Picker("ASR 引擎", selection: $draft.asrProviderID) {
                    Text("Whisper (mlx-community/whisper-small-mlx)").tag("whisper")
                }
                Text("更多引擎（SFSpeech、Whisper Large 等）将在后续版本支持。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.formStyle(.grouped)
    }

    // MARK: Hotkey Tab
    private static let modifierOptions: [(String, String)] = [
        ("option", "⌥ Option"), ("command", "⌘ Command"),
        ("control", "⌃ Control"), ("shift", "⇧ Shift"),
    ]

    private var hotkeyTab: some View {
        Form {
            Section("全局唤醒快捷键") {
                HStack {
                    Text("修饰键")
                    Spacer()
                    ForEach(Self.modifierOptions, id: \.0) { id, label in
                        Toggle(label, isOn: Binding(
                            get: { draft.hotkeyModifiers.contains(id) },
                            set: { on in
                                if on { draft.hotkeyModifiers.append(id) }
                                else { draft.hotkeyModifiers.removeAll { $0 == id } }
                            }
                        )).toggleStyle(.button)
                    }
                }
                HStack {
                    Text("当前配置")
                    Spacer()
                    Text(hotkeyDescription).foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
                Text("目前按键固定为 Space（keyCode 49）。更多按键选择将在后续版本添加。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var hotkeyDescription: String {
        let m: [String: String] = ["option":"⌥","command":"⌘","control":"⌃","shift":"⇧"]
        return draft.hotkeyModifiers.compactMap { m[$0] }.joined() + "Space"
    }

    // MARK: Output Tab
    private var outputTab: some View {
        Form {
            Section("默认输出方式") {
                Picker("接受后动作", selection: $draft.defaultOutputMode) {
                    Text("复制到剪贴板").tag("copy")
                    Text("直接注入光标位置").tag("inject")
                }
                if draft.defaultOutputMode == "inject" {
                    Text("写入剪贴板后模拟 ⌘V 注入光标。原剪贴板内容将在 1 秒后恢复。\n需要辅助功能权限（Accessibility）。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }.formStyle(.grouped)
    }
}
```

- [ ] **Step 4: 更新 StatusBarController 支持菜单**

```swift
// Sources/Phrased/App/StatusBarController.swift
import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem!
    private let onOpen: () -> Void
    private let onSettings: () -> Void
    private let onHistory: () -> Void

    init(
        onOpen: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onHistory: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onSettings = onSettings
        self.onHistory = onHistory
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Phrased")
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 Phrased",    action: #selector(doOpen),     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "历史记录",        action: #selector(doHistory),  keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…",           action: #selector(doSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Phrased",    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func doOpen()     { onOpen() }
    @objc private func doSettings() { onSettings() }
    @objc private func doHistory()  { onHistory() }
}
```

- [ ] **Step 5: 更新 AppDelegate 连接所有设置**

```swift
// Sources/Phrased/App/AppDelegate.swift
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: HotkeyManager?
    private var phrasedWindowController: PhrasedWindowController?
    private var settingsWindowController: SettingsWindowController?

    private var settings = PhrasedSettings.loadOrDefault()
    private lazy var processor = IntentProcessor()
    private lazy var inputVM = InputViewModel()
    private lazy var confirmVM = ConfirmViewModel(llm: makeLLMProvider(), processor: processor)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        phrasedWindowController = PhrasedWindowController(inputVM: inputVM, confirmVM: confirmVM)
        inputVM.onSubmit = { [weak self] text, template in
            guard let self else { return }
            self.confirmVM.start(input: text, template: template)
        }
        inputVM.setAudioSource(settings.audioSource == "microphone" ? .microphone : .systemAudio)

        statusBarController = StatusBarController(
            onOpen:     { [weak self] in self?.showWindow() },
            onSettings: { [weak self] in self?.showSettings() },
            onHistory:  { [weak self] in self?.showHistory() }
        )
        hotkeyManager = HotkeyManager(
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyNSModifiers,
            onActivate: { [weak self] in self?.showWindow() }
        )
        inputVM.warmUpTranscriber()
    }

    private func makeLLMProvider() -> LLMProvider {
        switch settings.llmProviderID {
        case "openai":
            return OpenAICompatibleProvider(
                baseURL: settings.openAIBaseURL,
                apiKey: settings.openAIAPIKey,
                model: settings.openAIModel
            )
        default:
            return OllamaLLMProvider(model: settings.ollamaModel)
        }
    }

    private func showWindow() { phrasedWindowController?.show() }

    private func showSettings() {
        // Always recreate so settings reflects current state
        settingsWindowController = SettingsWindowController(
            settings: settings,
            onSave: { [weak self] newSettings in
                guard let self else { return }
                self.settings = newSettings
                try? newSettings.save()
                self.hotkeyManager?.update(
                    keyCode: newSettings.hotkeyKeyCode,
                    modifiers: newSettings.hotkeyNSModifiers
                )
                self.confirmVM.updateProvider(self.makeLLMProvider())
                self.inputVM.setAudioSource(newSettings.audioSource == "microphone" ? .microphone : .systemAudio)
                // Notify windowController of new templates (Phase 3)
                self.phrasedWindowController?.updateTemplates(newSettings.allTemplates)
            }
        )
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showHistory() {
        // Wired in Phase 6
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
```

> `phrasedWindowController?.updateTemplates(...)` 是 Phase 3 才实现的方法，此处可先留存 `// TODO: Phase 3` 注释或定义空 stub。

- [ ] **Step 6: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 7: 手动测试**

```bash
make package && open .build/release/Phrased.app
# 验证：菜单栏右键 → 三个菜单项存在
# 打开设置 → 四个 Tab 正常显示
# 修改 LLM 供应商 → 保存 → 再打开设置 → 值已保存
```

- [ ] **Step 8: Commit**

```bash
git add Sources/Phrased/Settings/ Sources/Phrased/App/ Sources/Phrased/Input/HotkeyManager.swift
git commit -m "feat: settings window (model/audio/hotkey/output), dynamic hotkey, menu bar"
```

---

## Phase 3: Custom Prompt Templates

### Task 3.1: PromptTemplate Model

**Files:**
- Create: `Sources/Phrased/Core/PromptTemplate.swift`
- Create: `Tests/PhrasedTests/PromptTemplateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PhrasedTests/PromptTemplateTests.swift
import XCTest
@testable import Phrased

final class PromptTemplateTests: XCTestCase {
    func test_builtins_notEmpty() {
        XCTAssertFalse(PromptTemplate.builtins.isEmpty)
    }

    func test_autoTemplate_hasNilInstruction() {
        let auto = PromptTemplate.builtins.first { $0.id == "auto" }
        XCTAssertNil(auto?.promptInstruction)
    }

    func test_customTemplate_roundTrip() throws {
        let t = PromptTemplate(id: "t1", name: "Test", promptInstruction: "Be brief.")
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(PromptTemplate.self, from: data)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.promptInstruction, "Be brief.")
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter PromptTemplateTests`
Expected: FAIL

- [ ] **Step 3: Create PromptTemplate**

```swift
// Sources/Phrased/Core/PromptTemplate.swift
import Foundation

struct PromptTemplate: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var promptInstruction: String?  // nil = no style override

    static let builtins: [PromptTemplate] = [
        .init(id: "auto",         name: "通用",      promptInstruction: nil),
        .init(id: "formal",       name: "正式",      promptInstruction: "语气正式，用词严谨，适合商务或官方场合。"),
        .init(id: "concise",      name: "简洁",      promptInstruction: "尽量精简，去掉冗余，保留核心意思。"),
        .init(id: "casual",       name: "随性",      promptInstruction: "语气轻松随意，像朋友之间说话。"),
        .init(id: "professional", name: "专业",      promptInstruction: "专业术语准确，逻辑清晰，适合行业内沟通。"),
        .init(id: "polite",       name: "礼貌",      promptInstruction: "措辞礼貌周到，态度温和。"),
        .init(id: "ai_prompt",    name: "AI 提示词", promptInstruction: "改写为适合发送给 AI 的提示词：意图明确、结构清晰、包含必要上下文、去除口语化表达，必要时拆解为背景/任务/要求三部分。"),
    ]
}

extension PhrasedSettings {
    var allTemplates: [PromptTemplate] { PromptTemplate.builtins + customTemplates }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter PromptTemplateTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Phrased/Core/PromptTemplate.swift Tests/PhrasedTests/PromptTemplateTests.swift
git commit -m "feat: PromptTemplate model with builtins, PhrasedSettings.allTemplates"
```

---

### Task 3.2: 迁移 WritingStyle → PromptTemplate

**Files:**
- Modify: `Sources/Phrased/Core/IntentProcessor.swift`
- Modify: `Sources/Phrased/Confirm/ConfirmViewModel.swift`
- Modify: `Sources/Phrased/Input/InputWindow.swift`
- Modify: `Sources/Phrased/Confirm/ConfirmWindow.swift`

- [ ] **Step 1: 更新 IntentProcessor**

```swift
// IntentProcessor.swift — 把 buildMessages 的 style 参数换成 template：
func buildMessages(input: String, feedback: String?, template: PromptTemplate = PromptTemplate.builtins[0]) -> [LLMMessage] {
    var styleInstruction = ""
    if let instruction = template.promptInstruction {
        styleInstruction = "\n风格要求：\(instruction)"
    }
    // ... 其余不变，删除 WritingStyle enum
}
```

删除文件里的 `WritingStyle` enum（整个删掉）。

- [ ] **Step 2: 更新 ConfirmViewModel**

```swift
private(set) var currentTemplate: PromptTemplate = PromptTemplate.builtins[0]

func start(input: String, template: PromptTemplate = PromptTemplate.builtins[0]) {
    originalInput = input
    currentTemplate = template
    streamedResult = ""; feedbackText = ""; showFeedbackField = false; didCopy = false
    generate(feedback: nil)
}

// generate() 里：
let messages = processor.buildMessages(input: originalInput, feedback: feedback, template: currentTemplate)
```

- [ ] **Step 3: 更新 InputViewModel**

```swift
@Published var selectedTemplate: PromptTemplate = PromptTemplate.builtins[0]
var onSubmit: ((String, PromptTemplate) -> Void)?
```

- [ ] **Step 4: 更新 PhrasedView — 模板 Picker 支持动态列表**

`PhrasedWindowController` 需要持有并可更新模板列表。关键：用 `@Published` 让 SwiftUI 响应更新：

```swift
// 在 PhrasedWindowController 里加：
@Published var allTemplates: [PromptTemplate] = PromptTemplate.builtins

func updateTemplates(_ templates: [PromptTemplate]) {
    allTemplates = templates
    // 如果当前选中的模板被删除了，回退到 auto
    if !templates.contains(inputVM.selectedTemplate) {
        inputVM.selectedTemplate = PromptTemplate.builtins[0]
    }
}
```

`PhrasedView` 通过 `@ObservedObject` 监听 controller 的 `allTemplates` 变化：

```swift
// PhrasedView 新增参数：
@ObservedObject var windowController: PhrasedWindowController

private var stylePicker: some View {
    Picker("", selection: $inputVM.selectedTemplate) {
        ForEach(windowController.allTemplates) { t in
            Text(t.name).tag(t)
        }
    }
    .pickerStyle(.menu)
    .frame(width: 88)
    .labelsHidden()
}

// onChange 改为：
.onChange(of: inputVM.selectedTemplate) { newTemplate in
    guard showResult else { return }
    confirmVM.start(input: confirmVM.originalInput, template: newTemplate)
}
```

- [ ] **Step 5: 在 Settings 里加模板管理 Tab**

```swift
// SettingsView.swift 新增 templatesTab：
private var templatesTab: some View {
    VStack(spacing: 0) {
        List {
            Section("内置（只读）") {
                ForEach(PromptTemplate.builtins) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).bold()
                        Text(t.promptInstruction ?? "（无风格指令）")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Section("自定义") {
                ForEach($draft.customTemplates) { $t in
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("名称", text: $t.name)
                        TextField("提示词指令", text: Binding(
                            get: { t.promptInstruction ?? "" },
                            set: { t.promptInstruction = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical).lineLimit(3, reservesSpace: true).font(.caption)
                    }
                }
                .onDelete { draft.customTemplates.remove(atOffsets: $0) }
            }
        }
        HStack {
            Spacer()
            Button("添加模板") {
                draft.customTemplates.append(
                    PromptTemplate(id: UUID().uuidString, name: "新模板", promptInstruction: "")
                )
            }.buttonStyle(.bordered)
        }.padding()
    }
}
// 加入 TabView：
templatesTab.tabItem { Label("模板", systemImage: "text.badge.plus") }
```

- [ ] **Step 6: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add Sources/Phrased/Core/IntentProcessor.swift Sources/Phrased/Core/PromptTemplate.swift \
        Sources/Phrased/Confirm/ConfirmViewModel.swift Sources/Phrased/Confirm/ConfirmWindow.swift \
        Sources/Phrased/Input/InputWindow.swift Sources/Phrased/Settings/SettingsView.swift
git commit -m "feat: replace WritingStyle with PromptTemplate, dynamic template list, custom template editor"
```

---

## Phase 4: Context Capture

### Task 4.1: ContextCapture

**Files:**
- Create: `Sources/Phrased/Context/ContextCapture.swift`
- Create: `Tests/PhrasedTests/ContextCaptureTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PhrasedTests/ContextCaptureTests.swift
import XCTest
@testable import Phrased

final class ContextCaptureTests: XCTestCase {
    func test_captureReturnsValue() {
        let ctx = ContextCapture.capture()
        XCTAssertNotNil(ctx)
    }

    func test_emptyContext_isEmpty() {
        let ctx = InputContext(frontmostApp: nil, selectedText: nil, clipboardText: nil)
        XCTAssertTrue(ctx.isEmpty)
    }

    func test_withApp_notEmpty() {
        let ctx = InputContext(frontmostApp: nil, selectedText: nil, clipboardText: "hello")
        XCTAssertFalse(ctx.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter ContextCaptureTests`
Expected: FAIL

- [ ] **Step 3: Create ContextCapture**

```swift
// Sources/Phrased/Context/ContextCapture.swift
import AppKit
import ApplicationServices

struct InputContext {
    var frontmostApp: NSRunningApplication?   // needed for TextInjector in Phase 5
    var frontmostAppName: String? { frontmostApp?.localizedName }
    var frontmostAppBundleID: String? { frontmostApp?.bundleIdentifier }
    var selectedText: String?
    var clipboardText: String?

    var isEmpty: Bool {
        frontmostApp == nil && selectedText == nil && clipboardText == nil
    }

    /// Suggest a template ID based on the frontmost app.
    var suggestedTemplateID: String? {
        guard let bundleID = frontmostAppBundleID else { return nil }
        let map: [String: String] = [
            "com.apple.mail":                    "formal",
            "com.microsoft.Outlook":             "formal",
            "com.tencent.xinWeChat":             "polite",
            "com.apple.Notes":                   "casual",
            "com.notion.id":                     "professional",
            "com.linear.app":                    "professional",
            "com.github.GitHubDesktop":          "concise",
            "com.openai.chat":                   "ai_prompt",
            "com.anthropic.claudefordesktop":    "ai_prompt",
        ]
        return map[bundleID]
    }
}

enum ContextCapture {
    /// Must be called BEFORE Phrased window is activated (while user's app is still frontmost).
    static func capture() -> InputContext {
        let app = NSWorkspace.shared.frontmostApplication
        let selected = selectedTextViaAccessibility(for: app)
        let clip = NSPasteboard.general.string(forType: .string)
        return InputContext(frontmostApp: app, selectedText: selected, clipboardText: clip)
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
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter ContextCaptureTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Phrased/Context/ContextCapture.swift Tests/PhrasedTests/ContextCaptureTests.swift
git commit -m "feat: ContextCapture with AX selected text, clipboard, frontmost app"
```

---

### Task 4.2: 传递 Context 至 LLM 提示词

**Files:**
- Modify: `Sources/Phrased/Core/IntentProcessor.swift`
- Modify: `Sources/Phrased/Confirm/ConfirmViewModel.swift`
- Modify: `Sources/Phrased/Confirm/ConfirmWindow.swift`
- Modify: `Sources/Phrased/App/AppDelegate.swift`

Context 流向设计：
```
AppDelegate.showWindow()
  → ContextCapture.capture()           // 此时用户 app 还是 frontmost
  → PhrasedWindowController.show(context:)
     → 存为 pendingContext
     → inputVM.onSubmit 闭包从 controller 读取 pendingContext
       → confirmVM.start(input:template:context:)
```

- [ ] **Step 1: IntentProcessor 接受 context**

```swift
func buildMessages(
    input: String,
    feedback: String?,
    template: PromptTemplate,
    context: InputContext = InputContext(frontmostApp: nil, selectedText: nil, clipboardText: nil)
) -> [LLMMessage] {
    // styleInstruction 同前...

    var contextBlock = ""
    if let selected = context.selectedText, !selected.isEmpty {
        contextBlock += "\n\n用户当前选中的文字（可作为参考上下文）：\n\(selected)"
    }
    if let clip = context.clipboardText, !clip.isEmpty, clip != input {
        contextBlock += "\n\n用户剪贴板内容：\n\(clip)"
    }
    if let appName = context.frontmostAppName {
        contextBlock += "\n\n来源应用：\(appName)"
    }

    var userContent = """
    你是用户的个人语言助手。
    将以下输入理解为用户的真实意图，改写为清晰、准确、适合直接使用的文字。
    保持简洁，只输出改写后的文字，不要添加多余解释。\(styleInstruction)\(contextBlock)

    用户输入：\(input)
    """
    if let feedback, !feedback.isEmpty {
        userContent += "\n\n用户对上一次结果不满意，补充说明：\(feedback)\n\n请重新生成。"
    }
    return [LLMMessage(role: "user", content: userContent)]
}
```

- [ ] **Step 2: ConfirmViewModel 存储并传递 context**

```swift
private(set) var currentContext = InputContext(frontmostApp: nil, selectedText: nil, clipboardText: nil)

func start(input: String, template: PromptTemplate, context: InputContext = .init(frontmostApp: nil, selectedText: nil, clipboardText: nil)) {
    originalInput = input
    currentTemplate = template
    currentContext = context
    streamedResult = ""; feedbackText = ""; showFeedbackField = false; didCopy = false
    generate(feedback: nil)
}

// generate() 里：
let messages = processor.buildMessages(input: originalInput, feedback: feedback, template: currentTemplate, context: currentContext)
```

- [ ] **Step 3: PhrasedWindowController 接收并暂存 context**

```swift
// 在 PhrasedWindowController 里加：
private var pendingContext = InputContext(frontmostApp: nil, selectedText: nil, clipboardText: nil)

func show(context: InputContext = InputContext(frontmostApp: nil, selectedText: nil, clipboardText: nil)) {
    pendingContext = context
    // 自动应用 suggested template
    if let suggestedID = context.suggestedTemplateID,
       let template = allTemplates.first(where: { $0.id == suggestedID }) {
        inputVM.selectedTemplate = template
    }
    // ... 其余原 show() 逻辑不变 ...
}
```

`inputVM.onSubmit` 闭包需要捕获 `pendingContext`（在 AppDelegate 里设置的闭包）：

```swift
// AppDelegate:
inputVM.onSubmit = { [weak self] text, template in
    guard let self else { return }
    let context = self.phrasedWindowController?.pendingContext
        ?? InputContext(frontmostApp: nil, selectedText: nil, clipboardText: nil)
    self.confirmVM.start(input: text, template: template, context: context)
}
```

- [ ] **Step 4: AppDelegate.showWindow() 在激活前 capture**

```swift
private func showWindow() {
    let context = ContextCapture.capture()  // 必须在 NSApp.activate 之前调用
    phrasedWindowController?.show(context: context)
}
```

- [ ] **Step 5: 在输入框下显示来源 app 标签**

在 `PhrasedView.inputBar` 的 `inputArea` 外层加一行小字：

```swift
// inputBar VStack 顶部加（当有 frontmostApp 时显示）：
if let appName = phrasedWindowController?.pendingContext.frontmostAppName {
    HStack {
        Image(systemName: "app.badge")
            .font(.caption2).foregroundColor(.secondary.opacity(0.5))
        Text(appName)
            .font(.caption2).foregroundColor(.secondary.opacity(0.6))
        Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.top, 6)
}
```

- [ ] **Step 6: 启动时请求 Accessibility 权限**

```swift
// AppDelegate.applicationDidFinishLaunching 末尾加：
if !AXIsProcessTrusted() {
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}
```

- [ ] **Step 7: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 8: Commit**

```bash
git add Sources/Phrased/Core/IntentProcessor.swift Sources/Phrased/Confirm/ConfirmViewModel.swift \
        Sources/Phrased/Confirm/ConfirmWindow.swift Sources/Phrased/App/AppDelegate.swift
git commit -m "feat: context capture — selected text, clipboard, frontmost app auto-style, AX permission request"
```

---

## Phase 5: Direct Text Injection

### Task 5.1: TextInjector

**Files:**
- Create: `Sources/Phrased/Output/TextInjector.swift`
- Modify: `Sources/Phrased/Confirm/ConfirmViewModel.swift`
- Modify: `Sources/Phrased/Confirm/ConfirmWindow.swift`

- [ ] **Step 1: Create TextInjector**

```swift
// Sources/Phrased/Output/TextInjector.swift
import AppKit

enum TextInjector {
    /// Save clipboard → write text → activate target app → simulate ⌘V → restore clipboard after 1s.
    static func inject(_ text: String, into targetApp: NSRunningApplication?) async {
        let pasteboard = NSPasteboard.general

        // 1. Snapshot clipboard
        let savedItems: [(types: [NSPasteboard.PasteboardType], data: [NSPasteboard.PasteboardType: Data])] =
            (pasteboard.pasteboardItems ?? []).map { item in
                let types = item.types
                var data: [NSPasteboard.PasteboardType: Data] = [:]
                types.forEach { if let d = item.data(forType: $0) { data[$0] = d } }
                return (types: types, data: data)
            }

        // 2. Write new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Activate target app
        if let app = targetApp {
            app.activate(options: [])
            try? await Task.sleep(nanoseconds: 120_000_000)  // 120ms for activation
        }

        // 4. Simulate ⌘V
        simulatePaste()

        // 5. Restore clipboard after 1 second
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            pasteboard.clearContents()
            for item in savedItems {
                item.data.forEach { type, data in pasteboard.setData(data, forType: type) }
            }
        }
    }

    private static func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
```

- [ ] **Step 2: 更新 ConfirmViewModel.accept()**

```swift
func accept(outputMode: String = "copy") {
    let text = streamedResult
    let targetApp = currentContext.frontmostApp

    if outputMode == "inject" {
        Task { @MainActor in
            await TextInjector.inject(text, into: targetApp)
        }
    } else {
        ClipboardOutput.copy(text)
    }

    didCopy = true
    if !isLocked {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.onDismiss?()
        }
    }
}
```

- [ ] **Step 3: 更新 actionBar 接受按钮**

```swift
// ConfirmWindow.swift actionBar 里，accept 按钮改为：
// outputMode 从 settings 传入（或直接从 PhrasedWindowController 读取）
let outputMode: String  // "copy" | "inject"，由 init 传入

Button(confirmVM.didCopy
       ? (outputMode == "inject" ? "已注入 ✓" : "已复制 ✓")
       : (outputMode == "inject" ? "注入到光标" : "接受并复制")) {
    confirmVM.accept(outputMode: outputMode)
}
.keyboardShortcut(.return)
// ... 其余样式不变
```

- [ ] **Step 4: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 5: 手动测试**

在 TextEdit 打开文档，光标定位后按 ⌥Space，输入文字，点击"注入到光标"，验证文字出现在光标位置，1 秒后剪贴板恢复。

- [ ] **Step 6: Commit**

```bash
git add Sources/Phrased/Output/TextInjector.swift Sources/Phrased/Confirm/ConfirmViewModel.swift \
        Sources/Phrased/Confirm/ConfirmWindow.swift
git commit -m "feat: TextInjector — clipboard swap + ⌘V injection, restore clipboard after 1s"
```

---

## Phase 6: History

### Task 6.1: HistoryStore

**Files:**
- Create: `Sources/Phrased/History/HistoryStore.swift`
- Create: `Tests/PhrasedTests/HistoryStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PhrasedTests/HistoryStoreTests.swift
import XCTest
@testable import Phrased

final class HistoryStoreTests: XCTestCase {
    var store: HistoryStore!
    var tmpURL: URL!

    override func setUp() {
        tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        store = HistoryStore(storageURL: tmpURL)
    }

    func test_appendAndLoad() throws {
        let e = HistoryEntry(id: UUID(), createdAt: Date(), input: "hi", output: "Hello!", templateName: "通用", appName: nil)
        try store.append(e)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].input, "hi")
    }

    func test_emptyOnMissingFile() throws {
        XCTAssertTrue(try store.load().isEmpty)
    }

    func test_cappedAt500() throws {
        for i in 0..<505 {
            try store.append(HistoryEntry(id: UUID(), createdAt: Date(), input: "\(i)", output: "", templateName: "", appName: nil))
        }
        XCTAssertEqual(try store.load().count, 500)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter HistoryStoreTests`
Expected: FAIL

- [ ] **Step 3: Create HistoryStore**

```swift
// Sources/Phrased/History/HistoryStore.swift
import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var input: String
    var output: String
    var templateName: String
    var appName: String?
}

class HistoryStore {
    private let storageURL: URL

    init(storageURL: URL = HistoryStore.defaultStorageURL()) {
        self.storageURL = storageURL
    }

    static func defaultStorageURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Phrased", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    func load() throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HistoryEntry].self, from: Data(contentsOf: storageURL))
    }

    func append(_ entry: HistoryEntry) throws {
        var entries = (try? load()) ?? []
        entries.append(entry)
        if entries.count > 500 { entries = Array(entries.suffix(500)) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try encoder.encode(entries).write(to: storageURL, options: .atomic)
    }

    func clear() throws {
        try FileManager.default.removeItem(at: storageURL)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter HistoryStoreTests`
Expected: PASS

- [ ] **Step 5: 在 ConfirmViewModel.accept() 里写入历史**

```swift
// ConfirmViewModel 的 accept() 开头加：
let entry = HistoryEntry(
    id: UUID(), createdAt: Date(),
    input: originalInput, output: streamedResult,
    templateName: currentTemplate.name,
    appName: currentContext.frontmostAppName
)
try? historyStore.append(entry)
```

`historyStore` 是注入的依赖：
```swift
private let historyStore: HistoryStore

init(llm: LLMProvider, processor: IntentProcessor, historyStore: HistoryStore = HistoryStore()) {
    self.llm = llm
    self.processor = processor
    self.historyStore = historyStore
}
```

- [ ] **Step 6: Commit**

```bash
git add Sources/Phrased/History/HistoryStore.swift Tests/PhrasedTests/HistoryStoreTests.swift \
        Sources/Phrased/Confirm/ConfirmViewModel.swift
git commit -m "feat: HistoryStore JSON append-log, write entry on accept"
```

---

### Task 6.2: History Window

**Files:**
- Create: `Sources/Phrased/History/HistoryWindowController.swift`
- Modify: `Sources/Phrased/App/AppDelegate.swift`

- [ ] **Step 1: Create HistoryWindowController**

```swift
// Sources/Phrased/History/HistoryWindowController.swift
import AppKit
import SwiftUI

class HistoryWindowController: NSWindowController {
    init(store: HistoryStore) {
        let hosting = NSHostingController(rootView: HistoryView(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Phrased 历史记录"
        window.contentViewController = hosting
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
}

struct HistoryView: View {
    let store: HistoryStore
    @State private var entries: [HistoryEntry] = []

    var body: some View {
        List(entries.reversed()) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.templateName)
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    if let app = entry.appName {
                        Text(app).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(entry.createdAt, style: .relative)
                        .font(.caption2).foregroundColor(.secondary)
                }
                Text(entry.input)
                    .font(.system(size: 13)).foregroundColor(.secondary)
                Text(entry.output)
                    .font(.system(size: 13)).textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
        .onAppear { entries = (try? store.load()) ?? [] }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("清空历史") { try? store.clear(); entries = [] }
            }
        }
    }
}
```

- [ ] **Step 2: 连接 AppDelegate.showHistory()**

```swift
// AppDelegate:
private var historyWindowController: HistoryWindowController?
private lazy var historyStore = HistoryStore()

private func showHistory() {
    if historyWindowController == nil {
        historyWindowController = HistoryWindowController(store: historyStore)
    }
    historyWindowController?.showWindow(nil)
    historyWindowController?.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

// confirmVM 初始化时传入 historyStore：
private lazy var confirmVM = ConfirmViewModel(llm: makeLLMProvider(), processor: processor, historyStore: historyStore)
```

- [ ] **Step 3: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/Phrased/History/HistoryWindowController.swift Sources/Phrased/App/AppDelegate.swift
git commit -m "feat: history window — list all entries, copy result, clear history"
```

---

## Phase 7: Vocabulary / Hot Words

### Task 7.1: VocabularyStore

**Files:**
- Create: `Sources/Phrased/Vocabulary/VocabularyStore.swift`
- Create: `Tests/PhrasedTests/VocabularyStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PhrasedTests/VocabularyStoreTests.swift
import XCTest
@testable import Phrased

final class VocabularyStoreTests: XCTestCase {
    func test_replacesWholeWord() {
        let store = VocabularyStore(words: [VocabEntry(trigger: "tmr", expansion: "tomorrow")])
        XCTAssertEqual(store.apply(to: "tmr I'll be there"), "tomorrow I'll be there")
    }

    func test_noSubstringReplacement() {
        let store = VocabularyStore(words: [VocabEntry(trigger: "imo", expansion: "in my opinion")])
        XCTAssertEqual(store.apply(to: "import this"), "import this")
    }

    func test_noMatch_returnsOriginal() {
        let store = VocabularyStore(words: [VocabEntry(trigger: "abc", expansion: "xyz")])
        XCTAssertEqual(store.apply(to: "no match"), "no match")
    }

    func test_roundTripPersistence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vocab_\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = VocabularyStore(words: [VocabEntry(trigger: "g2g", expansion: "got to go")])
        try store.save(to: url)
        let loaded = try VocabularyStore.load(from: url)
        XCTAssertEqual(loaded.words.first?.trigger, "g2g")
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter VocabularyStoreTests`
Expected: FAIL

- [ ] **Step 3: Create VocabularyStore**

```swift
// Sources/Phrased/Vocabulary/VocabularyStore.swift
import Foundation

struct VocabEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var trigger: String
    var expansion: String
}

class VocabularyStore {
    private(set) var words: [VocabEntry]

    init(words: [VocabEntry] = []) { self.words = words }

    func apply(to text: String) -> String {
        var result = text
        for entry in words where !entry.trigger.isEmpty {
            guard let regex = try? NSRegularExpression(
                pattern: "(?<![\\w])\\Q\(entry.trigger)\\E(?![\\w])"
            ) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: entry.expansion)
        }
        return result
    }

    static func defaultStorageURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Phrased", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("vocabulary.json")
    }

    func save(to url: URL = VocabularyStore.defaultStorageURL()) throws {
        try JSONEncoder().encode(words).write(to: url, options: .atomic)
    }

    static func load(from url: URL = VocabularyStore.defaultStorageURL()) throws -> VocabularyStore {
        let words = try JSONDecoder().decode([VocabEntry].self, from: Data(contentsOf: url))
        return VocabularyStore(words: words)
    }

    static func loadOrDefault() -> VocabularyStore { (try? load()) ?? VocabularyStore() }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter VocabularyStoreTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Phrased/Vocabulary/VocabularyStore.swift Tests/PhrasedTests/VocabularyStoreTests.swift
git commit -m "feat: VocabularyStore whole-word regex replacement, JSON persistence"
```

---

### Task 7.2: 连接热词 + Settings Tab

**Files:**
- Modify: `Sources/Phrased/Input/InputWindow.swift`
- Modify: `Sources/Phrased/App/AppDelegate.swift`
- Modify: `Sources/Phrased/Settings/SettingsView.swift`

- [ ] **Step 1: InputViewModel.submit() 应用热词**

```swift
// InputViewModel.submit() 里：
let raw = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
let finalText = vocabularyStore.apply(to: raw)
guard !finalText.isEmpty else { return }
onSubmit?(finalText, selectedTemplate)
inputText = ""

// InputViewModel 新增：
var vocabularyStore: VocabularyStore = VocabularyStore()
```

- [ ] **Step 2: AppDelegate 初始化时注入 vocabularyStore**

```swift
private lazy var vocabularyStore = VocabularyStore.loadOrDefault()

// 在 applicationDidFinishLaunching 里：
inputVM.vocabularyStore = vocabularyStore
```

- [ ] **Step 3: Settings 新增热词 Tab**

```swift
// SettingsView.swift 新增：
@State private var vocabWords: [VocabEntry] = VocabularyStore.loadOrDefault().words

private var vocabularyTab: some View {
    VStack(spacing: 0) {
        Text("热词会在提交时自动替换（整词匹配）。例：输入 "tmr" → 自动展开为 "tomorrow"。")
            .font(.caption).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top])

        List {
            ForEach($vocabWords) { $entry in
                HStack {
                    TextField("触发词", text: $entry.trigger).frame(width: 100)
                    Text("→").foregroundColor(.secondary)
                    TextField("展开为", text: $entry.expansion)
                }
            }
            .onDelete { vocabWords.remove(atOffsets: $0) }
        }

        HStack {
            Spacer()
            Button("添加热词") {
                vocabWords.append(VocabEntry(trigger: "", expansion: ""))
            }.buttonStyle(.bordered)
        }.padding()
    }
    .onChange(of: vocabWords) { words in
        try? VocabularyStore(words: words).save()
    }
}

// 加入 TabView：
vocabularyTab.tabItem { Label("热词", systemImage: "text.word.spacing") }
```

- [ ] **Step 4: Build 确认无错**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/Phrased/Input/InputWindow.swift Sources/Phrased/App/AppDelegate.swift \
        Sources/Phrased/Settings/SettingsView.swift
git commit -m "feat: vocabulary substitution on submit, hot-word management in settings"
```

---

## 权限清单（最终交付前检查）

| 权限 | 用途 | 阶段 |
|---|---|---|
| `NSMicrophoneUsageDescription` | MicrophoneCapture | Phase 2 |
| `NSSpeechRecognitionUsageDescription` | 保留（Whisper 不需要，SFSpeech 需要） | — |
| `NSScreenCaptureUsageDescription` | SystemAudioCapture | 已有 |
| Accessibility (`AXIsProcessTrusted`) | 选中文字 + ⌘V 注入 | Phase 4–5 |
| 网络 | OpenAI API | Phase 1 |

---

## 阶段依赖关系

```
Phase 0（Bug 修复）
    ↓
Phase 1（Protocol 抽象）
    ↓
Phase 2（Settings + 音频源）
    ↓
Phase 3   Phase 4   Phase 6   Phase 7
（模板）  （Context） （历史）  （热词）
              ↓
          Phase 5（注入）
```

Phase 3、4、6、7 在 Phase 2 完成后可以并行或任意顺序推进。Phase 5 依赖 Phase 4（需要 `InputContext.frontmostApp`）。
