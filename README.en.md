# Phrased

**English** | [中文](README.md)

> Turn rough voice or text into polished, ready-to-use writing — in any app, instantly.

Invoke a floating input panel with a global hotkey, speak or type, pick a style, and get AI-rewritten text injected at the cursor. Phrased works with any OpenAI-compatible language model and speech recognition service, local or cloud.

---

## ✨ Features

**🎤 Input**
- Global hotkey (default: double-tap `Control`) opens a floating panel over any app
- Type directly or use voice — microphone or system audio capture
- Captured text from the frontmost app pre-fills the input

**🤖 AI Rewriting**
- Four built-in styles: Auto, Formal, Concise, AI Prompt
- Auto mode adapts tone to the target app (email → formal, messaging → casual)
- Add custom prompt templates
- Inline feedback loop: describe what to adjust and regenerate

**📋 Output**
- Text is injected directly at the cursor

**🗣️ Speech Recognition**
- Built-in macOS speech recognition — offline on Apple silicon, no setup required
- Local: any OpenAI-compatible endpoint (llama.cpp + Whisper, faster-whisper, etc.)
- Cloud: Groq Whisper (extremely fast), Alibaba Cloud ASR, or any compatible API
- Transcription is editable before you submit

**🧠 Language Model**
- Local: Ollama, LM Studio, Jan, llama.cpp — scan and add automatically
- Cloud: OpenAI, DeepSeek, Moonshot, Groq, Mistral, ZhipuAI, Alibaba Cloud, or any OpenAI-compatible endpoint
- API keys stored in Keychain, never written to disk

**📚 History**
- All inputs and outputs saved locally
- Search, filter by style / source app / date, group by date / style / app
- Export to TXT, JSON, or CSV

**⚙️ Other**
- Text substitution: define triggers that expand on submit (`tmr` → `tomorrow`)
- Fully configurable in-app and global hotkeys
- Localized: English and Chinese (Simplified)
- Settings backup and restore (JSON export/import)

---

## 🖥️ Requirements

- macOS 14 Sonoma or later
- Apple silicon or Intel Mac
- For AI features: a running local model or cloud API key

---

## 📦 Installation

### Download (recommended)

Download the latest `Phrased-x.x.x.dmg` from the [Releases](https://github.com/Noah0025/Phrased/releases) page, open it, and drag **Phrased.app** to your **Applications** folder.

Because Phrased is not notarized, macOS will block it on first launch. To open it:

**Option A — one-time terminal command (fastest):**
```bash
xattr -d com.apple.quarantine /Applications/Phrased.app
```

**Option B — System Settings:**
Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the Phrased warning.

### Build from source

```bash
git clone https://github.com/Noah0025/Phrased.git
cd Phrased
make package
open Phrased.app
```

Requires Xcode Command Line Tools (`xcode-select --install`).

---

## 🔐 Permissions

Phrased requests the following permissions on first use:

| Permission | Why |
|---|---|
| **Accessibility** | Simulate ⌘V to inject text at the cursor |
| **Microphone** | Record voice input |
| **Screen Recording** | Capture system audio for transcription |
| **Speech Recognition** | Use built-in macOS speech recognition |

---

## 🚀 Quick Start

### 1. Language Model

#### Route A — Local model (free, private, runs offline)

**Step 1: Install a local model runner**

| App | Models | Install |
|---|---|---|
| [Ollama](https://ollama.com) | Llama, Qwen, Mistral, Gemma… | `brew install ollama` or download from site |
| [LM Studio](https://lmstudio.ai) | Same library, GUI-based | Download from site |
| [Jan](https://jan.ai) | Same library, open source | Download from site |

**Step 2: Download a model**

With Ollama (recommended):
```bash
ollama pull qwen2.5:7b     # good balance of speed and quality, ~4 GB
ollama pull llama3.2:3b    # faster, lighter, ~2 GB
```

A 7B+ parameter model is recommended for rewriting tasks. Larger models produce noticeably better results.

**Step 3: Connect Phrased**

Open **Settings → Language Model**, click **Scan Local Models** — Phrased finds running services automatically and lists available models. Click **Add**.

#### Route B — Cloud API (no local setup required)

Pick a provider, get an API key, and enter it in **Settings → Language Model → Templates**.

| Provider | Free tier | Notes |
|---|---|---|
| [DeepSeek](https://platform.deepseek.com) | ❌ | Excellent quality, very low cost, pay-per-use |
| [Groq](https://console.groq.com) | ✅ free models | Extremely fast inference, rate limited |
| [OpenAI](https://platform.openai.com) | ❌ | GPT-4o, industry standard |
| [Moonshot (Kimi)](https://platform.moonshot.cn) | ❌ | Strong Chinese support, pay-per-use |
| [Alibaba Cloud](https://bailian.console.aliyun.com) | ✅ trial credits | Qwen models, strong Chinese support, check website for details |
| [Mistral](https://console.mistral.ai) | ✅ free models | Good European option, rate limited |
| [ZhipuAI](https://open.bigmodel.cn) | ✅ free models | GLM-4-Flash series available for free |

In Phrased: **Settings → Language Model → Templates** → select provider → enter API key → done.

---

### 2. Speech Recognition

#### Route A — Local / Built-in (free, runs offline)

**macOS built-in recognizer (recommended for new users)**

No setup required — works out of the box. Fully offline on Apple silicon; Intel Macs require an internet connection. Just tap the microphone button in Phrased.

**Local Whisper service (higher accuracy)**

Run a compatible service such as [faster-whisper-server](https://github.com/fedirz/faster-whisper-server) or [whisper.cpp](https://github.com/ggerganov/whisper.cpp), then open **Settings → Audio & Speech** and click **Scan Local Services** — Phrased detects and adds it automatically. If nothing is found, click **Add Manually** in the prompt to enter the address yourself.

#### Route B — Cloud speech recognition

| Provider | Free tier | Notes |
|---|---|---|
| [Groq](https://console.groq.com) | ✅ free quota | Whisper large-v3, extremely fast — recommended |
| [Alibaba Cloud](https://bailian.console.aliyun.com) | ✅ trial credits | Strong Chinese accuracy, check website for details |

In Phrased: **Settings → Audio & Speech → Templates** → select provider → enter API key → done.

---

## ⚙️ Setup

### 1. Language model

Open **Settings → Language Model**. Choose one:

- **Local**: click **Scan Local Models** — Phrased detects running Ollama, LM Studio, Jan, and llama.cpp instances automatically. Or click **Templates** to pick a cloud provider and enter your API key.
- **Cloud**: click **Templates**, select a provider (OpenAI, DeepSeek, etc.), enter the base URL and API key.

The base URL should be the root of the API (e.g. `https://api.openai.com`) — Phrased appends `/v1/chat/completions` automatically.

### 2. Speech recognition

Open **Settings → Audio & Speech**. Choose one:

- **Built-in**: macOS native recognizer, offline on Apple silicon, no configuration needed.
- **Local**: enter the address of a running Whisper-compatible service (e.g. faster-whisper, whisper.cpp).
- **Cloud**: click **Templates**, select a provider (Groq, Alibaba Cloud, etc.), enter the base URL and API key.

The base URL format is the same as for the language model (e.g. `https://api.groq.com`) — Phrased appends `/v1/audio/transcriptions` automatically.

### 3. Hotkey

Open **Settings → Hotkey**. The default global hotkey is double-tap `Control`. You can change it to any modifier combination or modifier + key.

---

## 📖 Usage

1. Press the global hotkey — the input panel appears near the mouse cursor
2. Type or press the microphone button to dictate
3. Select a style (Auto / Formal / Concise / AI Prompt)
4. Press `⌘↩` to submit
5. Review the result; press `⌘⇧A` to re-dictate, `⌘E` to give feedback, `⌘R` to regenerate
6. Press `⌘I` (inject) or `⌘C` (copy) to use the result

The panel dismisses automatically when you switch apps. Use `⌘P` to pin it.

---

## 🎨 Prompt Templates

Phrased ships with four built-in templates (Auto, Formal, Concise, AI Prompt). Add custom ones in **Settings → Prompt Templates**. Each template can define a fixed system instruction; leave it blank to use auto mode (Phrased adapts tone based on the frontmost app).

---

## 🏗️ Architecture

```
Sources/Phrased/
├── App/          AppDelegate, StatusBarController, LaunchAtLoginHelper
├── Confirm/      Floating panel — PhrasedView, ConfirmViewModel, PhrasedWindowController
├── Context/      ContextCapture (selected text + frontmost app)
├── Core/         IntentProcessor, PromptTemplate, KeychainHelper, LocalServiceScanner
│   └── Providers/ OpenAICompatibleProvider, LLMProvider, ASRProvider
├── History/      HistoryStore, HistoryWindowController, HistoryExporter
├── Input/        InputViewModel, AudioCapture, MicrophoneCapture, HotkeyManager,
│                 SFSpeechTranscriber, CloudASRTranscriber, WhisperTranscriber
├── Output/       TextInjector, ClipboardOutput
├── Settings/     PhrasedSettings, SettingsView, all Panes, LLMProfile, ASRProfile
├── UI/           DesignTokens, ExpandableCard
└── Vocabulary/   VocabularyStore
```

Built with Swift, SwiftUI, and Swift Package Manager. No third-party dependencies.

---

## ⚠️ Known Limitations

- **Accessibility permission resets on rebuild**: codesigning with an ad-hoc identity (`--sign -`) ties the permission to the binary hash. After rebuilding from source, re-grant Accessibility in System Settings.
- **Screen Recording permission**: same applies — required for system audio capture, re-grant after rebuild.
- **Not notarized**: Phrased is distributed outside the Mac App Store and is not notarized. Use the `xattr` command above to clear the quarantine flag after downloading.
- **Not on the Mac App Store**: sandboxing constraints are incompatible with the keyboard injection mechanism.

---

## 📄 License

MIT + Commons Clause — © 2025 LNZ. Free to use and modify; commercial use prohibited. See [LICENSE](LICENSE) for details.
