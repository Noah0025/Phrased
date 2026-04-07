# Phrased 重设计规格文档

**日期**：2026-04-02  
**版本**：v1.0  
**状态**：待审阅

---

## 一、产品定位

Phrased 是一个**个人语言中间层（Personal Language OS）**。

核心价值：在用户的原始表达（模糊、跳跃、多语言混杂）和最终输出之间插入一个本地 AI 层，理解用户真实意图，转化为更清晰、更适合目标场景的文字。随着使用时间积累，系统越来越懂用户的表达习惯。

竞品均不具备：意图理解 + 用户确认层 + 长期习惯学习 的完整组合。

---

## 二、第一版功能范围

### 2.1 输入层
- **文字输入**：全局快捷键呼出输入框，用户直接打字
- **语音输入**：在输入框内一键切换录音模式，复用现有 `AudioCapture` + `SpeechTranscriber`，转录结果填入输入框后统一走处理层

### 2.2 触发方式
- 全局快捷键（默认 `⌥Space`，可在设置中修改）
- 菜单栏图标点击

### 2.3 核心处理层
- 本地 Ollama，默认模型 `qwen2.5:7b`
- 处理流程：原始输入 + 用户画像 → 构造 prompt → Ollama 流式输出改写结果
- 用户画像第一版为空 JSON 结构，预留字段，学习层后续填充

### 2.4 确认层
- 模态弹窗，显示：原始输入（上）+ 改写结果（下，流式逐字出现）
- 三个操作：
  - **接受** → 复制到剪贴板，关闭窗口
  - **重新生成** → 清空结果，重新调用 Ollama
  - **修改意见** → 文本框输入补充说明，附加到 prompt 后重新生成

### 2.5 输出层
- 接受后自动复制到系统剪贴板（`NSPasteboard`）
- 用户手动 Cmd+V 粘贴到目标 App
- 文字注入（Accessibility API）列为后续版本

### 2.6 菜单栏
- 常驻菜单栏，无 Dock 图标
- 菜单项：打开输入框 / 偏好设置 / 退出

---

## 三、架构设计

```
输入层
  ├── HotkeyManager        全局快捷键监听
  ├── InputWindow          输入框（文字/语音切换）
  └── SpeechTranscriber    语音转文字（复用现有代码）

核心处理层
  ├── IntentProcessor      构造 prompt，调用 Ollama
  ├── OllamaClient         Ollama HTTP 流式接口封装
  └── UserProfile          用户画像（JSON，第一版为空结构）

确认层
  ├── ConfirmWindow        模态弹窗，流式显示结果
  └── FeedbackHandler      处理修改意见，追加 prompt 重新生成

输出层
  └── ClipboardOutput      写入系统剪贴板

菜单栏
  └── AppDelegate + StatusBarController
```

### 关键设计原则
- **异步隔离**：AudioCapture / Ollama 调用全部在独立异步 Task，不阻塞主线程（解决现有 Phrased 卡顿问题）
- **流式输出**：OllamaClient 使用 URLSession stream，逐 token 回调更新 ConfirmWindow
- **单一职责**：每个模块只做一件事，InputWindow 不感知 Ollama，ConfirmWindow 不感知剪贴板
- **预留扩展点**：输入层设计为协议，后续可加任意触发方式；输出层设计为协议，后续可加注入方式

---

## 四、用户画像数据结构（预留）

```json
{
  "version": 1,
  "updatedAt": "",
  "language": {
    "preferred_output": "en",
    "preferred_input": "zh"
  },
  "style": {
    "tone": "",
    "formality": "",
    "patterns": []
  },
  "history_summary": "",
  "contexts": []
}
```

第一版不填充，IntentProcessor 构造 prompt 时若字段为空则跳过注入。

---

## 五、Prompt 设计

### 基础 prompt（无用户画像）
```
你是用户的个人语言助手。
将以下输入理解为用户的真实意图，改写为清晰、准确、适合直接使用的文字。
保持简洁，不要添加多余解释。

用户输入：{input}
```

### 带用户画像
```
你是用户的个人语言助手。以下是用户的语言偏好：
{user_profile}

将以下输入理解为用户的真实意图，改写为清晰、准确的文字。
输出语言：{preferred_output}

用户输入：{input}
```

### 带修改意见（重新生成）
```
（原始 prompt）

用户对上一次生成结果不满意，补充说明如下：
{feedback}

请重新生成。
```

---

## 六、技术选型

| 项目 | 选择 | 理由 |
|------|------|------|
| 语言 | Swift 5.9 | 原生 macOS，App Store 分发，macOS/iOS 代码复用 |
| UI | SwiftUI | 声明式，后续 iOS 迁移成本低 |
| 本地模型 | Ollama（`qwen2.5:7b`） | 已有基础设施，中英文最强 7B |
| 流式输出 | URLSession + AsyncStream | 原生，无额外依赖 |
| 快捷键 | CGEventTap / Carbon API | macOS 全局快捷键标准方案 |
| 剪贴板 | NSPasteboard | 系统原生 |

---

## 七、不在第一版范围内

- 文字注入（Accessibility API）
- 用户习惯学习（定时蒸馏 pipeline）
- iOS App
- 联网接口
- 知识库问答
- 语音合成输出
- 多触发方式（选中文字触发等）

---

## 八、成功标准

第一版验收标准：
1. 全局快捷键呼出输入框，响应 < 100ms
2. 文字输入后，Ollama 流式结果在确认窗口逐字出现
3. 语音输入转录结果正确填入输入框
4. 接受后内容正确写入剪贴板
5. 修改意见后重新生成结果不同于上一次
6. 全程 CPU/内存占用正常，不卡顿
