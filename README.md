# Phrased

[English](README.en.md) | **中文**

> 将语音或粗糙的文字输入即时转化为表达流畅、随时可用的文本——在任意应用中均可使用。

通过全局快捷键唤出浮动输入面板，语音或文字输入，选择写作风格，AI 改写后的文本直接注入光标位置。Phrased 兼容任何 OpenAI 兼容的语言模型和语音识别服务，支持本地部署或云端 API。

---

## ✨ 功能特性

**🎤 输入**
- 全局快捷键（默认：双击 `Control`）在任意应用上方唤出浮动面板
- 直接输入或语音录入——支持麦克风和系统音频
- 自动读取当前应用中的选中文本作为上下文

**🤖 AI 改写**
- 四种内置风格：自动、正式、简洁、AI 提示词
- 自动模式根据目标应用调整语气（邮件→正式，即时通讯→随意）
- 支持添加自定义提示词模板
- 内联反馈循环：描述修改意见后可重新生成

**📋 输出**
- 通过模拟 ⌘V 将文本注入光标位置（需要辅助功能权限）
- 自动回退为剪贴板复制
- 1 秒后自动还原原始剪贴板内容

**🗣️ 语音识别**
- 内置 macOS 语音识别，Apple 芯片离线可用，无需配置
- 本地：任意 OpenAI 兼容端点（llama.cpp + Whisper、faster-whisper 等）
- 云端：Groq Whisper（速度极快）、阿里云语音识别，或任意兼容 API
- 转写结果可编辑，提交前随时修改

**🧠 语言模型**
- 本地：Ollama、LM Studio、Jan、llama.cpp——自动扫描并添加
- 云端：OpenAI、DeepSeek、月之暗面、Groq、Mistral、智谱 AI、阿里云百炼，或任意 OpenAI 兼容端点
- API Key 存储于系统钥匙串，不写入磁盘

**📚 历史记录**
- 所有输入和输出均保存在本地
- 支持搜索、按风格 / 来源应用 / 日期筛选，按日期 / 风格 / 应用分组
- 导出为 TXT、JSON 或 CSV

**⚙️ 其他**
- 文本替换：定义触发词，提交时自动展开（如 `tmr` → `tomorrow`）
- 应用内快捷键和全局快捷键均可自定义
- 支持中英文界面
- 设置备份与恢复（JSON 导入/导出）

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

在 Phrased 中：**设置 → 语言模型 → 模板** → 选择服务商 → 填入 API Key → 完成。

---

### 二、语音识别

#### 路线 A——本地 / 内置（免费、离线可用）

**macOS 内置识别器（推荐新手）**

无需任何配置，开箱即用。Apple 芯片设备完全离线运行，Intel Mac 需联网。打开 Phrased 后直接点击麦克风按钮即可使用。

**本地 Whisper 服务（更高精度）**

运行 [faster-whisper](https://github.com/SYSTRAN/faster-whisper) 或 [whisper.cpp](https://github.com/ggerganov/whisper.cpp) 等兼容服务后，在 **设置 → 音频与语音** 中填入服务地址即可。

#### 路线 B——云端语音识别

| 服务商 | 免费额度 | 备注 |
|---|---|---|
| [Groq](https://console.groq.com) | ✅ 有免费额度 | Whisper large-v3，速度极快，推荐首选 |
| [阿里云语音识别](https://bailian.console.aliyun.com) | ✅ 有试用额度 | 中文识别准确率高，额度以官网为准 |

在 Phrased 中：**设置 → 音频与语音 → 模板** → 选择服务商 → 填入 API Key → 完成。

---

## ⚙️ 配置说明

### 1. 语言模型

打开 **设置 → 语言模型**，选择其中一种：

- **本地**：点击 **扫描本地模型**——Phrased 自动检测运行中的 Ollama、LM Studio、Jan、llama.cpp 实例。或点击 **模板** 选择云端服务商并填入 API Key。
- **云端**：点击 **模板**，选择服务商（OpenAI、DeepSeek 等），填入 Base URL 和 API Key。

Base URL 填写 API 根地址（如 `https://api.openai.com`），Phrased 会自动追加 `/v1/chat/completions`。

### 2. 语音识别

打开 **设置 → 音频与语音**，选择其中一种：

- **内置**：macOS 原生识别器，Apple 芯片设备离线可用，无需任何配置。
- **本地**：填入运行中的 Whisper 兼容服务地址（如 faster-whisper、whisper.cpp）。
- **云端**：点击 **模板**，选择服务商（Groq、阿里云等），填入 Base URL 和 API Key。

Base URL 格式与语言模型相同（如 `https://api.groq.com`），Phrased 会自动追加 `/v1/audio/transcriptions`。

### 3. 快捷键

打开 **设置 → 快捷键**。默认全局快捷键为双击 `Control`，可修改为任意修饰键组合或修饰键加按键。

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

## 🏗️ 架构

```
Sources/Phrased/
├── App/          AppDelegate, StatusBarController, LaunchAtLoginHelper
├── Confirm/      浮动面板 — PhrasedView, ConfirmViewModel, PhrasedWindowController
├── Context/      ContextCapture（选中文本 + 当前应用）
├── Core/         IntentProcessor, PromptTemplate, KeychainHelper, LocalServiceScanner
│   └── Providers/ OpenAICompatibleProvider, LLMProvider, ASRProvider
├── History/      HistoryStore, HistoryWindowController, HistoryExporter
├── Input/        InputViewModel, AudioCapture, MicrophoneCapture, HotkeyManager,
│                 SFSpeechTranscriber, CloudASRTranscriber, WhisperTranscriber
├── Output/       TextInjector, ClipboardOutput
├── Settings/     PhrasedSettings, SettingsView, 各设置面板, LLMProfile, ASRProfile
├── UI/           DesignTokens, ExpandableCard
└── Vocabulary/   VocabularyStore
```

使用 Swift、SwiftUI 和 Swift Package Manager 构建，无第三方依赖。

---

## ⚠️ 已知限制

- **辅助功能权限在重新构建后失效**：使用临时签名身份（`--sign -`）时，权限绑定到二进制文件的哈希值。从源码重新构建后，需在系统设置中重新授予辅助功能权限。
- **屏幕录制权限**：同上——系统音频捕获必需，重新构建后需重新授权。
- **未经公证**：Phrased 在 Mac App Store 之外分发且未经 Apple 公证。下载后请使用上方 `xattr` 命令清除隔离标志。
- **未上架 Mac App Store**：沙箱限制与键盘注入机制不兼容。

---

## 📄 许可证

MIT + Commons Clause — © 2025 LNZ. 可自由使用和修改，禁止商业用途。详见 [LICENSE](LICENSE)。
