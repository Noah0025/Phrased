import Foundation
import AVFoundation

/// Sends recorded audio to an OpenAI-compatible /v1/audio/transcriptions endpoint.
class CloudASRTranscriber: ASRProvider {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private let baseURL: String
    private let apiKey: String
    private let model: String

    private var audioFile: AVAudioFile?
    private var tempURL: URL?
    private var transcribeTask: Task<Void, Never>?

    init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        self.apiKey = apiKey
        self.model = model.isEmpty ? "whisper-1" : model
    }

    func warmUp() {}

    func startSession() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        tempURL = url
        audioFile = nil
    }

    func stopSession() {
        let url = tempURL
        audioFile = nil
        tempURL = nil
        guard let fileURL = url else {
            DispatchQueue.main.async { self.onFinal?("") }
            return
        }
        transcribeTask?.cancel()
        transcribeTask = Task { await self.transcribe(fileURL: fileURL) }
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard tempURL != nil else { return }
        do {
            if audioFile == nil, let url = tempURL {
                audioFile = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            }
            try audioFile?.write(from: buffer)
        } catch {}
    }

    private func transcribe(fileURL: URL) async {
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transcribePath = OpenAICompatibleProvider.chatCompletionsPath(for: baseURL)
            .replacingOccurrences(of: "/chat/completions", with: "/audio/transcriptions")
        guard let endpoint = URL(string: "\(baseURL)\(transcribePath)"),
              let audioData = try? Data(contentsOf: fileURL) else {
            let err = NSError(domain: "CloudASR", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("error.asr.invalid_audio_or_url", comment: "")])
            DispatchQueue.main.async { self.onError?(err) }
            return
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        // model field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        // file field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let msg: String
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let err = json["error"] as? [String: Any],
                   let errMsg = err["message"] as? String {
                    msg = "HTTP \(http.statusCode): \(errMsg)"
                } else {
                    msg = "HTTP \(http.statusCode)"
                }
                let err = NSError(domain: "CloudASR", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: msg])
                DispatchQueue.main.async { self.onError?(err) }
                return
            }
            let text = (try? JSONDecoder().decode(TranscriptionResponse.self, from: data))?.text ?? ""
            DispatchQueue.main.async { self.onFinal?(text) }
        } catch {
            DispatchQueue.main.async { self.onError?(error) }
        }
    }

    private struct TranscriptionResponse: Decodable {
        let text: String
    }
}
