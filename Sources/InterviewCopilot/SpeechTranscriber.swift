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
            print("[Speech] Auth: \(status.rawValue)")
        }
    }

    func startSession() {
        beginRecognitionTask()
        scheduleSegmentReset()
    }

    func stopSession() {
        segmentTimer?.invalidate()
        segmentTimer = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func recentTranscript(lastSegments: Int = 5) -> String {
        transcriptHistory.suffix(lastSegments).joined(separator: " ")
    }

    private func beginRecognitionTask() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true   // Enable auto-punctuation for better sentence detection
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
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
            if error != nil {
                // Restart on error (common at 60s limit)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.beginRecognitionTask()
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
