import Foundation
import Speech
import AVFoundation

class SpeechTranscriber: NSObject {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?

    private(set) var transcriptHistory: [String] = []
    private var segmentTimer: Timer?
    private let segmentDuration: TimeInterval = 55
    private var isStopped = true
    private var isRestarting = false

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

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func recentTranscript(lastSegments: Int = 5) -> String {
        transcriptHistory.suffix(lastSegments).joined(separator: " ")
    }

    private func beginRecognitionTask() {
        guard !isStopped, !isRestarting else { return }
        isRestarting = true

        // Cancel previous task — will trigger error callback which we ignore via isRestarting
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        guard recognizer.isAvailable else {
            logDebug("[Speech] recognizer not available, retry in 5s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, !self.isStopped else { return }
                self.isRestarting = false
                self.beginRecognitionTask()
            }
            return
        }

        // Small delay to let the old task fully clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.createNewTask()
        }
    }

    private func createNewTask() {
        guard !isStopped else { isRestarting = false; return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request
        isRestarting = false

        logDebug("[Speech] new recognition task starting")
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, !self.isRestarting else { return }

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
                    // Final result = task ended, restart for continuous recognition
                    logDebug("[Speech] isFinal, restarting")
                    self.beginRecognitionTask()
                }
            }
            if let error = error as NSError? {
                guard !self.isStopped, !self.isRestarting else { return }
                logDebug("[Speech] error: \(error.localizedDescription) code=\(error.code)")
                // Restart after delay — let audio accumulate
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, !self.isStopped else { return }
                    self.beginRecognitionTask()
                }
            }
        }
    }

    private func scheduleSegmentReset() {
        segmentTimer?.invalidate()
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            guard let self, !self.isStopped, self.recognitionTask != nil else { return }
            logDebug("[Speech] segment timer: restarting recognition")
            self.beginRecognitionTask()
        }
    }
}
