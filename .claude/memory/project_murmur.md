---
name: Murmur 面试辅助工具
description: macOS 本地面试 Copilot — 系统音频捕获 + 实时翻译字幕 + Ollama 回答建议
type: project
---

## 项目信息
- **名称**：Murmur
- **GitHub**：https://github.com/Noah0025/Murmur（私有）
- **本机目录**：~/Projects/InterviewCopilot/
- **状态**：按钮 bug 已修复，SpeechTranscriber 重启逻辑已重写，需最终集成测试

## 两个核心功能
1. **实时翻译字幕**（自动持续）：系统音频 → SFSpeechRecognizer → Ollama(gemma3:4b) 纠错+中文翻译 → 浮层显示
2. **回答建议**（手动按住触发）：抓取最近问句 → Ollama(gemma3:4b) + interview_context.txt → 英文回答建议流式显示

## 技术栈
- Swift + SPM，`make package` 打包 .app bundle
- ScreenCaptureKit 捕获系统音频
- SFSpeechRecognizer 本地英语识别（55s 分段重启）
- Ollama gemma3:4b
- NSPanel 非激活浮层（.fullSizeContentView + frame-based bottomBar）

## 翻译管线
- 2-line refinement prompt（纠正英文 + 中文翻译），5/5 可靠性
- Fragment (<5 words) 自动合并到前一 block，跳过模型
- 输出验证：检查 ZH 含中文字符、EN 前缀匹配，失败则 fallback

## 已完成的修复
- **按钮失效 bug**：bottomBar 改 frame-based 布局，AppleScript 压力测试 8 轮 32 次点击零失败
- **SpeechTranscriber 无限重启**：用 isRestarting flag 过滤 cancel 错误，error 后 5 秒延迟重启
- **Makefile**：用 "Murmur Dev" 本地证书签名（需先在本机创建证书）

## 待完成
- **集成测试**：需打开 YouTube 音频，验证转写 → 断句 → 翻译完整流程（每次 rebuild 会失效 ScreenCaptureKit TCC 权限，授权一次后不要再 rebuild）
- **interview_context.txt**：填入 Tübingen PhD 面试准备内容
- **移除调试日志**：FloatingPanel.sendEvent 中的 logDebug、AppDelegate 中的额外日志

## 关键注意事项
- **TCC 权限**：ScreenCaptureKit 权限绑定 binary 的 CDHash，每次 rebuild 后必须重新授权屏幕录制。测试时先完成所有代码修改，build 一次，授权一次，然后只测试不重建
- **Ollama**：需本机运行 `ollama serve`，模型 gemma3:4b 需预先 pull
- **测试模式**：`open Murmur.app --args --test` 启动带文本输入框的测试模式
