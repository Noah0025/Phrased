import Foundation
import Speech
import AVFoundation

class SpeechTranscriber: NSObject {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Called every partial update (for live EN display)
    var onPartial: ((String) -> Void)?
    // Called only on finalized segments (for translation)
    var onFinal: ((String) -> Void)?

    private(set) var transcriptHistory: [String] = []
    private var segmentTimer: Timer?
    private let segmentDuration: TimeInterval = 50

    override init() {
        super.init()
        requestAuthorization()
    }

    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            logDebug("[Speech] Auth status: \(status.rawValue) (2=authorized)")
        }
    }

    func startSession() {
        logDebug("[Speech] startSession, recognizer available=\(recognizer.isAvailable)")
        isStopped = false
        consecutiveErrors = 0
        beginRecognitionTask()
        scheduleSegmentReset()
    }

    func stopSession() {
        isStopped = true
        segmentTimer?.invalidate()
        segmentTimer = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private var bufferCount = 0
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        bufferCount += 1
        if bufferCount % 100 == 1 {
            logDebug("[Speech] appendBuffer #\(bufferCount), frames=\(buffer.frameLength), request nil=\(recognitionRequest == nil)")
        }
        recognitionRequest?.append(buffer)
    }

    func recentTranscript(lastSegments: Int = 5) -> String {
        transcriptHistory.suffix(lastSegments).joined(separator: " ")
    }

    private var isStopped = false
    private var consecutiveErrors = 0

    private func beginRecognitionTask() {
        guard !isStopped else { return }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        guard recognizer.isAvailable else {
            logDebug("[Speech] recognizer not available, retry in 2s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.beginRecognitionTask()
            }
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request

        logDebug("[Speech] beginRecognitionTask starting")
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                self.consecutiveErrors = 0
                let text = result.bestTranscription.formattedString
                logDebug("[Speech] partial: \(text.prefix(60))...")
                DispatchQueue.main.async {
                    self.onPartial?(text)
                }
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.onFinal?(text)
                    }
                    self.transcriptHistory.append(text)
                    if self.transcriptHistory.count > 20 { self.transcriptHistory.removeFirst() }
                }
            }
            if let error = error {
                self.consecutiveErrors += 1
                logDebug("[Speech] error: \(error.localizedDescription), consecutive=\(self.consecutiveErrors)")
                guard !self.isStopped, self.consecutiveErrors < 5 else { return }
                let delay = min(Double(self.consecutiveErrors), 3.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.beginRecognitionTask()
                }
            }
        }
    }

    private func scheduleSegmentReset() {
        segmentTimer?.invalidate()
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            guard let self, self.recognitionTask != nil else { return }
            self.beginRecognitionTask()
        }
    }
}
