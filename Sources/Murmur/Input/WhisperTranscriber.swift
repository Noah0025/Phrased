import Foundation
import AVFoundation

class WhisperTranscriber: ASRProvider {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?

    private let model: String
    private var audioFile: AVAudioFile?
    private var tempURL: URL?
    private var transcribeTask: Task<Void, Never>?

    init(model: String = "mlx-community/whisper-small-mlx") {
        self.model = model.isEmpty ? "mlx-community/whisper-small-mlx" : model
    }

    private static let whisperPath: String = {
        let candidates = [
            "/Users/helm/Library/Python/3.9/bin/mlx_whisper",
            "/usr/local/bin/mlx_whisper",
            "/opt/homebrew/bin/mlx_whisper",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
    }()

    func warmUp() {
        let model = self.model
        Task.detached(priority: .background) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("murmur_warmup")
                .appendingPathExtension("wav")
            // Write 0.5s of silence as 16-bit PCM WAV
            let sampleRate: Int = 16000
            let numSamples = sampleRate / 2
            var wav = Data()
            func le16(_ v: Int16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
            func le32(_ v: Int32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
            let dataSize = Int32(numSamples * 2)
            wav += "RIFF".data(using: .ascii)!
            wav += le32(36 + dataSize)
            wav += "WAVEfmt ".data(using: .ascii)!
            wav += le32(16); wav += le16(1); wav += le16(1)
            wav += le32(Int32(sampleRate)); wav += le32(Int32(sampleRate * 2))
            wav += le16(2); wav += le16(16)
            wav += "data".data(using: .ascii)!
            wav += le32(dataSize)
            wav += Data(count: numSamples * 2)
            try? wav.write(to: url)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.whisperPath)
            process.arguments = [
                url.path,
                "--model", model,
                "--output-format", "txt",
                "--output-dir", url.deletingLastPathComponent().path,
            ]
            process.environment = [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
                "HOME": NSHomeDirectory(),
            ]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in c.resume() }
            }
            try? FileManager.default.removeItem(at: url)
            let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
            try? FileManager.default.removeItem(at: txtURL)
        }
    }

    func startSession() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        tempURL = url
        audioFile = nil
    }

    func stopSession() {
        let url = tempURL
        audioFile = nil  // closes the file
        tempURL = nil

        guard let fileURL = url else {
            DispatchQueue.main.async { self.onFinal?("") }
            return
        }

        transcribeTask?.cancel()
        transcribeTask = Task {
            await transcribe(fileURL: fileURL)
        }
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
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let txtURL = fileURL.deletingPathExtension().appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: txtURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.whisperPath)
        process.arguments = [
            fileURL.path,
            "--model", model,
            "--output-format", "txt",
            "--output-dir", fileURL.deletingLastPathComponent().path,
        ]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            DispatchQueue.main.async { self.onFinal?("") }
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }

        let text = (try? String(contentsOf: txtURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        DispatchQueue.main.async { self.onFinal?(text) }
    }
}
