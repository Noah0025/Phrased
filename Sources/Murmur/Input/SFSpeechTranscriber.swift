import Speech
import AVFoundation

class SFSpeechTranscriber: ASRProvider {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?

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
                    if result.isFinal {
                        self.onFinal?(text)
                    } else {
                        self.onPartial?(text)
                    }
                }
            } else if error != nil {
                DispatchQueue.main.async { self.onFinal?("") }
            }
        }
    }

    func stopSession() {
        request?.endAudio()
        // Don't cancel task — let it finish processing buffered audio
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }
}
