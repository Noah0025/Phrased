import Speech
import AVFoundation

class SFSpeechTranscriber: ASRProvider {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private let recognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func warmUp() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    func startSession() {
        task?.cancel()
        task = nil

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Prefer on-device; falls back to online automatically if unavailable
        req.requiresOnDeviceRecognition = (recognizer?.supportsOnDeviceRecognition == true)
        request = req

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.onPartial?(text)
                    }
                    if result.isFinal {
                        self.onFinal?(text)
                    }
                }
            } else if let error {
                DispatchQueue.main.async { self.onError?(error) }
            }
        }
    }

    func stopSession() {
        request?.endAudio()
        // finish() explicitly tells the task to stop accepting audio and deliver final result.
        // Falls back gracefully on older macOS (14.0+), harmless if unavailable.
        if #available(macOS 14.0, *) {
            task?.finish()
        }
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }
}
