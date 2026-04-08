<a name="chinese"></a>

<h1 align="center">Phrased</h1>

<p align="center"><strong>中文</strong> | <a href="#english">English</a></p>

> 语音或文字，一个快捷键，AI 帮你把话说清楚——在任意应用里都能用。

当我们说话或打字，表达的往往不是最清晰的版本。打字太快，发现写错了消息已经发出去；想跟人说件事，措辞却要想半天；知道自己想说什么，落到文字里却总差一口气——语气不对、结构散乱、太口语化。

现有的 AI 语音工具（如 Wispr Flow、Typeless）主打你说话、AI 来写，但价格不菲；改写工具（如 WritingTools）则需要你先认认真真写一段，再框选润色。Phrased 不想让你二选一：语音或文字，随时切换，一个快捷键唤出，轻量到不占你的注意力。

选好模型，挑好风格，剩下的交给 AI——哪怕你只是随手几个字，它也能拼出一段完整的表达。哪怕老板让你改了三十六遍稿子后说还是第一版好，你洋洋洒洒激情输入之后，AI 也能懂你真正想说的是：好的，老板。😉

完全开源，支持任意本地或云端模型，Phrased 不收集任何数据。

---

## ✨ 功能特性

**🎤 输入**
- 全局快捷键（默认：双击 `Control`）在任意应用上方唤出浮动面板
- 打字或语音都行——麦克风和系统音频都支持
- 自动读取当前应用中选中的文字作为上下文

**🤖 AI 改写**
- 四种内置风格：自动、正式、简洁、AI 提示词
- 自动模式会根据你在用的应用调整语气（发邮件就正式点，发消息就随意点）
- 可以加自定义提示词模板
- 结果不满意？说说哪儿不对，让它重新来过

**📋 输出**
- 直接打到光标处，不用手动粘贴

**🗣️ 语音识别**
- 内置 macOS 语音识别，Apple 芯片离线可用，开箱即用
- 本地：任意 OpenAI 兼容端点（llama.cpp + Whisper、faster-whisper 等）
- 云端：Groq Whisper（快到离谱）、阿里云语音识别，或任意兼容 API
- 转写内容可以直接改，不满意就编辑再提交

**🧠 语言模型**
- 本地：Ollama、LM Studio、Jan、llama.cpp——自动扫描，一键添加
- 云端：OpenAI、DeepSeek、月之暗面、Groq、Mistral、智谱 AI、阿里云百炼，或任意 OpenAI 兼容端点
- API Key 存在系统钥匙串里，不会写入磁盘

**📚 历史记录**
- 所有输入和输出都保存在本地
- 支持搜索，可按风格 / 来源应用 / 日期筛选，按日期 / 风格 / 应用分组
- 导出为 TXT、JSON 或 CSV

**⚙️ 其他**
- 文本替换：设置触发词，提交时自动展开（比如 `tmr` → `tomorrow`）
- 所有快捷键都可以自定义
- 界面支持中英文
- 设置可以导出备份，也可以导入恢复

---

## 🖥️ 系统要求

- macOS 14 Sonoma 或更高版本
- Apple 芯片或 Intel Mac
- AI 功能需要：本地运行的模型或云端 API Key

---

## 📦 安装

### 下载安装（推荐）

从 [Releases](https://github.com/Noah0025/Phrased/releases) 页面下载最新版 `Phrased-x.x.x.dmg`，打开后将 **Phrased.app** 拖入 **应用程序** 文件夹。

由于 Phrased 未经 Apple 公证，首次启动时 macOS 会阻止运行。解除方法：

**方案 A——终端命令（最快）：**
```bash
xattr -d com.apple.quarantine /Applications/Phrased.app
```

**方案 B——系统设置：**
前往 **系统设置 → 隐私与安全性**，向下滚动，点击 Phrased 旁边的 **仍要打开**。

### 从源码构建

```bash
git clone https://github.com/Noah0025/Phrased.git
cd Phrased
make package
open Phrased.app
```

需要 Xcode 命令行工具（`xcode-select --install`）。

---

## 🔐 权限说明

首次使用时，Phrased 会请求以下权限：

| 权限 | 用途 |
|---|---|
| **辅助功能** | 模拟 ⌘V 将文本注入光标位置 |
| **麦克风** | 录制语音输入 |
| **屏幕录制** | 捕获系统音频用于转写 |
| **语音识别** | 使用 macOS 内置语音识别 |

---

## 🚀 快速上手

### 一、语言模型

#### 路线 A——本地模型（免费、私密、离线可用）

**第一步：安装本地模型运行环境**

| 应用 | 支持模型 | 安装方式 |
|---|---|---|
| [Ollama](https://ollama.com) | Llama、Qwen、Mistral、Gemma… | `brew install ollama` 或官网下载 |
| [LM Studio](https://lmstudio.ai) | 同上，图形界面 | 官网下载 |
| [Jan](https://jan.ai) | 同上，开源 | 官网下载 |

**第二步：下载模型**

以 Ollama 为例（推荐）：
```bash
ollama pull qwen2.5:7b     # 速度与质量均衡，约 4 GB
ollama pull llama3.2:3b    # 更快更轻量，约 2 GB
```

改写任务推荐使用 7B 及以上参数量的模型，参数越大效果越明显。

**第三步：连接 Phrased**

打开 **设置 → 语言模型**，点击 **扫描本地模型**——Phrased 自动检测运行中的服务并列出可用模型，点击 **添加** 即可。

#### 路线 B——云端 API（无需本地配置）

选择一个服务商，获取 API Key，在 **设置 → 语言模型 → 模板** 中填入即可。

| 服务商 | 免费额度 | 备注 |
|---|---|---|
| [DeepSeek](https://platform.deepseek.com) | ❌ | 质量优秀，价格极低，按量计费 |
| [Groq](https://console.groq.com) | ✅ 有免费模型 | 推理速度极快，有速率限制 |
| [OpenAI](https://platform.openai.com) | ❌ | GPT-4o，行业标准 |
| [月之暗面 (Kimi)](https://platform.moonshot.cn) | ❌ | 中文支持强，按量计费 |
| [阿里云百炼](https://bailian.console.aliyun.com) | ✅ 有试用额度 | Qwen 系列，中文支持强，额度以官网为准 |
| [Mistral](https://console.mistral.ai) | ✅ 有免费模型 | 欧洲优质选项，有速率限制 |
| [智谱 AI](https://open.bigmodel.cn) | ✅ 有免费模型 | GLM-4-Flash 系列免费 |

以上为常见服务商示例，任何兼容 OpenAI API 格式的服务均可接入。Base URL 填写 API 根地址（如 `https://api.openai.com`），Phrased 会自动追加 `/v1/chat/completions`。

---

### 二、语音识别

#### 路线 A——本地 / 内置（免费、离线可用）

**macOS 内置识别器（推荐新手）**

无需任何配置，开箱即用。Apple 芯片设备完全离线运行，Intel Mac 需联网。打开 Phrased 后直接点击麦克风按钮即可使用。

**本地 Whisper 服务（更高精度）**

运行 [faster-whisper-server](https://github.com/fedirz/faster-whisper-server)、[whisper.cpp](https://github.com/ggerganov/whisper.cpp) 等兼容服务后，在 **设置 → 音频与语音** 点击 **扫描本地服务**——Phrased 自动检测并添加；若未找到，可点击弹窗中的 **手动添加** 填入服务地址。

#### 路线 B——云端语音识别

选择一个服务商，获取 API Key，在 **设置 → 音频与语音 → 模板** 中填入即可。

| 服务商 | 免费额度 | 备注 |
|---|---|---|
| [Groq](https://console.groq.com) | ✅ 有免费额度 | Whisper large-v3，速度极快，推荐首选 |
| [阿里云百炼](https://bailian.console.aliyun.com) | ✅ 有试用额度 | Paraformer，中文识别准确率高，额度以官网为准 |
| [OpenAI](https://platform.openai.com) | ❌ | Whisper-1，按量计费 |

Base URL 格式与语言模型相同（如 `https://api.groq.com/openai`），Phrased 会自动追加 `/v1/audio/transcriptions`。

---

### 三、快捷键

默认全局快捷键为双击 `Control`，可在 **设置 → 快捷键** 中修改为任意修饰键组合或修饰键加按键。

---

## 📖 使用方法

1. 按下全局快捷键——输入面板出现在鼠标附近
2. 输入文字，或点击麦克风按钮进行语音输入
3. 选择风格（自动 / 正式 / 简洁 / AI 提示词）
4. 按 `⌘↩` 提交
5. 查看结果；按 `⌘⇧A` 重新转写，`⌘E` 提供反馈，`⌘R` 重新生成
6. 按 `⌘I`（注入）或 `⌘C`（复制）使用结果

切换应用时面板自动关闭。按 `⌘P` 可固定面板。

---

## 🎨 提示词模板

Phrased 内置四种模板（自动、正式、简洁、AI 提示词）。在 **设置 → 提示词模板** 中可添加自定义模板。每个模板可定义固定的系统指令；留空则使用自动模式（Phrased 根据当前应用自动调整语气）。

---

## 🤝 参与贡献

欢迎提交 Issue 和 Pull Request。详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

## 🙏 致谢

代码实现由 [Claude Code](https://github.com/anthropics/claude-code)（[@anthropics](https://github.com/anthropics)）协助完成。

感谢以下项目和产品带来的灵感与支持：

- [Ollama](https://ollama.com) — 让本地模型的接入变得简单
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3) / [Qwen](https://github.com/QwenLM/Qwen) — 阿里巴巴通义千问系列语音与语言模型
- [OpenAI Whisper](https://github.com/openai/whisper) — 奠定了开源语音识别的基础
- [Wispr Flow](https://wisprflow.ai)、[Typeless](https://typeless.app)、[WritingTools](https://github.com/theJayTea/WritingTools)、[QuQu](https://github.com/yan5xu/ququ) — 为本项目提供了灵感

---

## ⚠️ 已知限制

- **辅助功能权限在重新构建后失效**：使用临时签名身份（`--sign -`）时，权限绑定到二进制文件的哈希值。从源码重新构建后，需在系统设置中重新授予辅助功能权限。
- **屏幕录制权限**：同上——系统音频捕获必需，重新构建后需重新授权。

---

## 📄 许可证

MIT + Commons Clause — © 2025 LNZ. 可自由使用和修改，禁止商业用途。详见 [LICENSE](LICENSE)。

使用 Swift、SwiftUI 和 Swift Package Manager 构建，无第三方依赖。

---

<a name="english"></a>

<h1 align="center">Phrased</h1>

<p align="center"><a href="#chinese">中文</a> | <strong>English</strong></p>

> Turn rough voice or text into polished, ready-to-use writing — in any app, instantly.

When we speak or type, what comes out is rarely our clearest version. You hit send before catching the typo; you spend five minutes searching for the right words; you know exactly what you mean but it just doesn't land right on the page — wrong tone, rambling structure, too casual.

AI voice tools like Wispr Flow and Typeless let you speak and have AI write it out, but they're expensive. Rewriting tools like WritingTools require you to write something properly first, then select and polish it. Phrased doesn't make you choose: voice or text, switch anytime, invoked with a hotkey, lightweight enough to stay out of your way.

Pick a model, pick a style, let AI handle the rest — even if you only jot down a few words, it'll shape them into something complete. And when your boss asks for the 36th revision only to say the first version was best, after all your passionate venting, Phrased knows what you actually want to send: "Sure, sounds good." 😉

Fully open-source, works with any local or cloud model, Phrased collects no data.

---

## ✨ Features

**🎤 Input**
- Global hotkey (default: double-tap `Control`) pops up a floating panel over any app
- Type or talk — microphone and system audio both work
- Selected text from the frontmost app is pulled in automatically

**🤖 AI Rewriting**
- Four built-in styles: Auto, Formal, Concise, AI Prompt
- Auto mode reads the room — formal for email, casual for chat
- Add your own prompt templates
- Not happy with the result? Tell it what's off and regenerate

**📋 Output**
- Goes straight to your cursor — no copy-paste needed

**🗣️ Speech Recognition**
- Built-in macOS speech recognition — offline on Apple silicon, zero setup
- Local: any OpenAI-compatible endpoint (llama.cpp + Whisper, faster-whisper, etc.)
- Cloud: Groq Whisper (absurdly fast), Alibaba Cloud ASR, or any compatible API
- Edit the transcript before submitting if it missed something

**🧠 Language Model**
- Local: Ollama, LM Studio, Jan, llama.cpp — auto-scanned, one click to add
- Cloud: OpenAI, DeepSeek, Moonshot, Groq, Mistral, ZhipuAI, Alibaba Cloud, or any OpenAI-compatible endpoint
- API keys live in Keychain, never on disk

**📚 History**
- Everything saved locally
- Search, filter by style / source app / date, group however you like
- Export to TXT, JSON, or CSV

**⚙️ Other**
- Text substitution: set triggers that expand on submit (`tmr` → `tomorrow`)
- All hotkeys are configurable
- English and Chinese UI
- Export and restore settings as JSON

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

The list above is a sample — any OpenAI-compatible endpoint works. Enter the base URL (e.g. `https://api.openai.com`) and API key; Phrased appends `/v1/chat/completions` automatically.

---

### 2. Speech Recognition

#### Route A — Local / Built-in (free, runs offline)

**macOS built-in recognizer (recommended for new users)**

No setup required — works out of the box. Fully offline on Apple silicon; Intel Macs require an internet connection. Just tap the microphone button in Phrased.

**Local Whisper service (higher accuracy)**

Run a compatible service such as [faster-whisper-server](https://github.com/fedirz/faster-whisper-server) or [whisper.cpp](https://github.com/ggerganov/whisper.cpp), then open **Settings → Audio & Speech** and click **Scan Local Services** — Phrased detects and adds it automatically. If nothing is found, click **Add Manually** in the prompt to enter the address yourself.

#### Route B — Cloud speech recognition

Pick a provider, get an API key, and enter it in **Settings → Audio & Speech → Templates**.

| Provider | Free tier | Notes |
|---|---|---|
| [Groq](https://console.groq.com) | ✅ free quota | Whisper large-v3, extremely fast — recommended |
| [Alibaba Cloud](https://bailian.console.aliyun.com) | ✅ trial credits | Paraformer, strong Chinese accuracy, check website for details |
| [OpenAI](https://platform.openai.com) | ❌ | Whisper-1, pay-per-use |

Base URL follows the same format (e.g. `https://api.groq.com/openai`); Phrased appends `/v1/audio/transcriptions` automatically.

---

### 3. Hotkey

The default global hotkey is double-tap `Control`. Change it in **Settings → Hotkey**.

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

## 🤝 Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

---

## 🙏 Acknowledgements

Built with the help of [Claude Code](https://github.com/anthropics/claude-code) by [@anthropics](https://github.com/anthropics).

Thanks to the following projects and products for inspiration:

- [Ollama](https://ollama.com) — making local models actually easy to run
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3) / [Qwen](https://github.com/QwenLM/Qwen) — Alibaba's Qwen family of speech and language models
- [OpenAI Whisper](https://github.com/openai/whisper) — set the foundation for open-source speech recognition
- [Wispr Flow](https://wisprflow.ai), [Typeless](https://typeless.app), [WritingTools](https://github.com/theJayTea/WritingTools), [QuQu](https://github.com/yan5xu/ququ) — for the inspiration

---

## ⚠️ Known Limitations

- **Accessibility permission resets on rebuild**: codesigning with an ad-hoc identity (`--sign -`) ties the permission to the binary hash. After rebuilding from source, re-grant Accessibility in System Settings.
- **Screen Recording permission**: same applies — required for system audio capture, re-grant after rebuild.

---

## 📄 License

MIT + Commons Clause — © 2025 LNZ. Free to use and modify; commercial use prohibited. See [LICENSE](LICENSE) for details.

Built with Swift, SwiftUI, and Swift Package Manager. No third-party dependencies.
