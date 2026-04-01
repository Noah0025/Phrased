import Foundation

/// Translation pipeline:
/// 1. Real-time: rough translation of current segment (fast, no context)
/// 2. On cut: context-aware re-translation of previous segment
///    using n-1 + n + n+1 start as context → replaces rough ZH

class SubtitleFeature {
    private let transcriber: SpeechTranscriber
    private let ollama: OllamaClient
    private let panel: FloatingPanel

    private var activeTask: Task<Void, Never>?
    private var isActiveStreaming = false
    private var translatedUpToCount: Int = 0

    private var refineTask: Task<Void, Never>?

    private var isSegmentActive = false
    private var lastRawPartial: String = ""
    private var segmentBaseLength: Int = 0

    /// Recent segment EN texts for context
    private var segmentHistory: [String] = []

    init(transcriber: SpeechTranscriber, ollama: OllamaClient, panel: FloatingPanel) {
        self.transcriber = transcriber
        self.ollama = ollama
        self.panel = panel
        bind()
    }

    private func bind() {
        transcriber.onPartial = { [weak self] rawText in
            guard let self else { return }
            self.lastRawPartial = rawText
            guard self.isSegmentActive else { return }

            let segmentText = self.extractSegmentText(rawText)
            guard !segmentText.isEmpty else { return }

            self.panel.updateSubtitleEN(segmentText)

            if !self.isActiveStreaming, segmentText.count > self.translatedUpToCount + 3 {
                self.translateActivePart(segmentText: segmentText)
            }
        }

        transcriber.onFinal = { [weak self] rawText in
            guard let self else { return }
            self.lastRawPartial = rawText
            guard self.isSegmentActive else { return }

            let segmentText = self.extractSegmentText(rawText)
            if !segmentText.isEmpty {
                self.panel.updateSubtitleEN(segmentText)
            }
            self.segmentBaseLength = 0
        }
    }

    // MARK: - Segment control

    func startSegment() {
        guard !isSegmentActive else { return }

        activeTask?.cancel()
        activeTask = nil
        isActiveStreaming = false

        let segmentText = extractSegmentText(lastRawPartial)
        if let detached = panel.detachActivePair() {
            let enText = segmentText.isEmpty ? (detached.enText) : segmentText
            if !enText.isEmpty {
                detached.markFinalized()        // isFinalized = true, immediately clickable
                detached.setStatusTranslating() // override to yellow while translating
                segmentHistory.append(enText)
                if segmentHistory.count > 4 { segmentHistory.removeFirst() }
                refineDetachedPair(pair: detached, enText: enText)
            } else {
                detached.markFinalized()
            }
        }

        isSegmentActive = true
        translatedUpToCount = 0
        segmentBaseLength = lastRawPartial.count
    }

    func stopSegment() {
        guard isSegmentActive else { return }
        isSegmentActive = false

        activeTask?.cancel()
        activeTask = nil
        isActiveStreaming = false

        let segmentText = extractSegmentText(lastRawPartial)
        if let detached = panel.detachActivePair() {
            let enText = segmentText.isEmpty ? (detached.enText) : segmentText
            if !enText.isEmpty {
                detached.markFinalized()        // isFinalized = true, immediately clickable
                detached.setStatusTranslating() // override to yellow while translating
                segmentHistory.append(enText)
                if segmentHistory.count > 4 { segmentHistory.removeFirst() }
                refineDetachedPair(pair: detached, enText: enText)
            } else {
                detached.markFinalized()
            }
        }
        translatedUpToCount = 0
    }

    // MARK: - Real-time rough translation

    private func translateActivePart(segmentText: String) {
        let newPart = untranslatedPart(of: segmentText)
        guard newPart.count > 3 else { return }

        let isFirst = (translatedUpToCount == 0)
        translatedUpToCount = segmentText.count

        isActiveStreaming = true
        let prompt = "翻译成中文，只输出中文翻译，不要拼音：\n\(newPart)"

        activeTask = Task {
            var isFirstChunk = true
            await self.ollama.streamTranslation(prompt: prompt) { chunk in
                guard !Task.isCancelled else { return }
                let first = isFirstChunk
                isFirstChunk = false
                DispatchQueue.main.async { [weak self] in
                    if first && isFirst {
                        self?.panel.updateSubtitleZH(chunk)
                    } else {
                        self?.panel.appendSubtitleZH(chunk)
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isActiveStreaming = false
                if self.isSegmentActive {
                    let current = self.extractSegmentText(self.lastRawPartial)
                    if current.count > self.translatedUpToCount + 3 {
                        self.translateActivePart(segmentText: current)
                    }
                }
            }
        }
    }

    // MARK: - Context-aware refinement (re-translate with context, same boundaries)

    private func refineDetachedPair(pair: SentencePairView, enText: String) {
        let originalWordCount = enText.split(separator: " ").count

        // Fragment (<5 words): skip model entirely, merge into previous block
        if originalWordCount < 5 {
            let historyIdx = segmentHistory.count - 1
            // Re-translate the merged block (prev EN + this fragment)
            let views = panel.sentenceStackViews()
            if let prevPair = views.last(where: { $0 !== pair && $0.isFinalized }),
               historyIdx > 0, historyIdx < segmentHistory.count {
                let mergedEN = prevPair.enText + " " + enText
                // Merge history
                segmentHistory[historyIdx - 1] = mergedEN
                segmentHistory.remove(at: historyIdx)
                // Merge in UI and re-translate the combined text
                panel.mergeIntoPrevious(pair: pair, combinedZH: "")
                simpleTranslate(pair: prevPair, text: mergedEN)
            } else {
                // No previous block, just translate as-is
                simpleTranslate(pair: pair, text: enText)
            }
            return
        }

        // First segment: simple translate, no context available
        guard segmentHistory.count >= 2 else {
            simpleTranslate(pair: pair, text: enText)
            return
        }

        // Context-aware refinement: 2-line output (corrected EN + ZH)
        let prevTexts = segmentHistory.dropLast()
        let prevContext = prevTexts.suffix(2).joined(separator: " ")
        let nextStart = isSegmentActive ? extractSegmentText(lastRawPartial) : ""

        var prompt = "参考上下文，纠正【】内的英文并翻译。只修复语音识别错误，不要增删内容。只翻译【】内的内容。\n"
        prompt += "输出两行：第一行纠正后的英文，第二行中文翻译。不要其他内容。\n\n"
        prompt += "前文：\(prevContext)\n"
        prompt += "【\(enText)】\n"
        if !nextStart.isEmpty {
            prompt += "后文：\(nextStart)\n"
        }

        let historyIdx = segmentHistory.count - 1

        refineTask?.cancel()
        refineTask = Task {
            var result = ""
            await self.ollama.streamTranslation(prompt: prompt) { chunk in
                guard !Task.isCancelled else { return }
                result += chunk
            }
            guard !Task.isCancelled else {
                DispatchQueue.main.async { pair.markFinalized() }
                return
            }

            let lines = result.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if lines.count >= 2 {
                    let correctedEN = lines[0]
                    let zh = lines[1]
                    let zhHasChinese = zh.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }

                    // Validate: EN should start similarly to input (not context)
                    // and ZH should actually contain Chinese
                    let enPrefix = String(enText.lowercased().prefix(15))
                    let outPrefix = String(correctedEN.lowercased().prefix(15))
                    let prefixMatch = enPrefix == outPrefix ||
                        correctedEN.count <= enText.count + 20

                    if !zhHasChinese || (!prefixMatch && correctedEN.count > enText.count + 20) {
                        // Model confused — fallback to simple translate
                        self.simpleTranslate(pair: pair, text: enText)
                        return
                    }

                    let finalEN: String
                    if correctedEN.count <= enText.count + 20 {
                        pair.updateEN(correctedEN)
                        finalEN = correctedEN
                    } else {
                        finalEN = enText
                    }
                    pair.setZH(zh)
                    pair.markFinalized()
                    if historyIdx < self.segmentHistory.count {
                        self.segmentHistory[historyIdx] = finalEN
                    }
                } else if lines.count == 1 {
                    // Check if single line is Chinese (ZH only) or English
                    let hasChinese = lines[0].unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
                    if hasChinese {
                        pair.setZH(lines[0])
                        pair.markFinalized()
                    } else {
                        // Model only returned EN, do simple translate for ZH
                        self.simpleTranslate(pair: pair, text: enText)
                    }
                } else {
                    self.simpleTranslate(pair: pair, text: enText)
                }
            }
        }
    }

    private func simpleTranslate(pair: SentencePairView, text: String) {
        refineTask?.cancel()
        let prompt = "翻译成中文，只输出中文翻译，不要拼音：\n\(text)"

        refineTask = Task {
            var result = ""
            await self.ollama.streamTranslation(prompt: prompt) { chunk in
                guard !Task.isCancelled else { return }
                result += chunk
            }
            guard !Task.isCancelled else {
                DispatchQueue.main.async { pair.markFinalized() }
                return
            }
            let clean = result.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                if !clean.isEmpty {
                    pair.setZH(clean)
                }
                pair.markFinalized()
            }
        }
    }

    // MARK: - Helpers

    private func extractSegmentText(_ rawText: String) -> String {
        guard segmentBaseLength > 0, segmentBaseLength < rawText.count else {
            if segmentBaseLength == 0 { return rawText }
            return ""
        }
        let idx = rawText.index(rawText.startIndex, offsetBy: segmentBaseLength)
        return String(rawText[idx...]).trimmingCharacters(in: .whitespaces)
    }

    private func untranslatedPart(of text: String) -> String {
        guard translatedUpToCount < text.count else { return "" }
        let idx = text.index(text.startIndex, offsetBy: translatedUpToCount)
        return String(text[idx...]).trimmingCharacters(in: .whitespaces)
    }
}
