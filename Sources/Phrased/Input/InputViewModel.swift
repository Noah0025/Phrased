import SwiftUI
import AppKit
import Combine
import AVFoundation

@MainActor
class InputViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var editorHeight: CGFloat = 22
    @Published var isRecording: Bool = false
    @Published var isTranscribing: Bool = false
    @Published var transcribeError: String? = nil
    @Published var audioLevel: Float = 0
    @Published var selectedTemplate: PromptTemplate = PromptTemplate.builtins[0]
    @Published var allTemplates: [PromptTemplate] = PromptTemplate.builtins
    @Published var contextAppName: String? = nil
    @Published var availableDevices: [AudioDevice] = []
    @Published var settings: PhrasedSettings = PhrasedSettings()

    var onSubmit: ((String, PromptTemplate) -> Void)?

    private let audioCapture = AudioCapture()
    private let micCapture = MicrophoneCapture()
    private var transcriber: ASRProvider
    private var pendingSubmit = false
    private var sessionGeneration: UInt64 = 0
    private let deviceManager = AudioDeviceManager()
    var vocabularyStore: VocabularyStore = VocabularyStore()

    // Silence auto-stop: fires after this interval of silence once speech has been detected.
    private var silenceWorkItem: DispatchWorkItem?
    private let silenceTimeout: TimeInterval = 2.5
    private var hasReceivedPartial = false
    private var recordingBaseText: String = ""  // text in box before recording started

    // Transcribing timeout: if onFinal hasn't fired within this interval, clear the state.
    private var transcribingTimeoutItem: DispatchWorkItem?
    private let transcribingTimeout: TimeInterval = 2

    init(transcriber: ASRProvider = WhisperTranscriber()) {
        self.transcriber = transcriber
        availableDevices = deviceManager.devices
        deviceManager.$devices
            .receive(on: DispatchQueue.main)
            .assign(to: &$availableDevices)
        bindCallbacks(for: sessionGeneration)
    }

    private func bindCallbacks(for generation: UInt64) {
        transcriber.onPartial = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, generation == self.sessionGeneration, self.isRecording else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.hasReceivedPartial = true
                let base = self.recordingBaseText
                self.inputText = base.isEmpty ? text : base + " " + text
                self.rescheduleSilenceTimer()
            }
        }
        transcriber.onFinal = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, generation == self.sessionGeneration else { return }
                self.cancelSilenceTimer()
                self.cancelTranscribingTimeout()
                self.isTranscribing = false
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let base = self.recordingBaseText
                    self.inputText = base.isEmpty ? trimmed : base + " " + trimmed
                }
                self.recordingBaseText = ""
                if self.pendingSubmit {
                    self.pendingSubmit = false
                    let raw = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let final = self.vocabularyStore.apply(to: raw)
                    if !final.isEmpty { self.onSubmit?(final, self.selectedTemplate) }
                }
            }
        }
        transcriber.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, generation == self.sessionGeneration else { return }
                self.transcribeError = error.localizedDescription
                print("[InputViewModel] Transcriber failed: \(error)")
                self.cancelSilenceTimer()
                self.cancelTranscribingTimeout()
                self.pendingSubmit = false
                self.isRecording = false
                self.isTranscribing = false
                self.audioCapture.stop()
                self.micCapture.stop()
                self.transcriber.stopSession()
            }
        }
    }

    private func rescheduleSilenceTimer() {
        cancelSilenceTimer()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.stopRecording()
            }
        }
        silenceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + silenceTimeout, execute: item)
    }

    private func cancelSilenceTimer() {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
    }

    private func scheduleTranscribingTimeout() {
        transcribingTimeoutItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isTranscribing else { return }
                self.isTranscribing = false
                if self.pendingSubmit {
                    self.pendingSubmit = false
                    let raw = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let text = self.vocabularyStore.apply(to: raw)
                    if !text.isEmpty { self.onSubmit?(text, self.selectedTemplate) }
                }
            }
        }
        transcribingTimeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + transcribingTimeout, execute: item)
    }

    private func cancelTranscribingTimeout() {
        transcribingTimeoutItem?.cancel()
        transcribingTimeoutItem = nil
    }

    /// Sets the active audio source and persists the preference.
    /// Falls back to "systemAudio" if the chosen device is no longer available.
    /// No-op during an active recording — takes effect on the next session.
    func selectAudioSource(_ id: String) {
        guard !isRecording else { return }
        let resolvedID = deviceManager.contains(id: id) ? id : "systemAudio"
        settings.audioSource = resolvedID
        do { try settings.save() } catch { print("[InputViewModel] Failed to save settings: \(error)") }
    }

    func insertNewline() {
        inputText += "\n"
    }

    func submit() {
        if isRecording {
            pendingSubmit = true
            stopRecording()
            return
        }
        if isTranscribing {
            pendingSubmit = true
            return
        }
        let raw = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = vocabularyStore.apply(to: raw)
        guard !finalText.isEmpty else { return }
        onSubmit?(finalText, selectedTemplate)
    }

    func updateASRProvider(_ asr: ASRProvider) {
        transcriber = asr
        bindCallbacks(for: sessionGeneration)
    }

    func warmUpTranscriber() {
        transcriber.warmUp()
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        return min(sqrt(sum / Float(count)) * 8, 1.0)
    }

    private func startRecording() {
        let micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micAuthStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted {
                        self.startRecording()
                    } else {
                        self.transcribeError = NSLocalizedString("error.mic_permission_denied", comment: "")
                    }
                }
            }
            return
        }
        if micAuthStatus == .denied || micAuthStatus == .restricted {
            transcribeError = NSLocalizedString("error.mic_permission_denied", comment: "")
            return
        }

        cancelSilenceTimer()
        pendingSubmit = false
        hasReceivedPartial = false
        audioLevel = 0
        isRecording = true
        isTranscribing = false
        recordingBaseText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionGeneration &+= 1
        bindCallbacks(for: sessionGeneration)
        let generation = sessionGeneration
        transcribeError = nil
        transcriber.startSession()
        rescheduleSilenceTimer()
        if settings.isSystemAudio {
            audioCapture.onError = { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, generation == self.sessionGeneration else { return }
                    self.transcribeError = error.localizedDescription
                    print("[InputViewModel] Audio capture failed: \(error)")
                    self.cancelSilenceTimer()
                    self.cancelTranscribingTimeout()
                    self.pendingSubmit = false
                    self.isRecording = false
                    self.isTranscribing = false
                    self.audioCapture.stop()
                    self.transcriber.stopSession()
                }
            }
            audioCapture.start { [weak self] buffer in
                self?.transcriber.appendBuffer(buffer)
            }
        } else {
            let uid = settings.audioSource
            micCapture.onDeviceLost = { [weak self] in
                guard let self else { return }
                // Device disconnected mid-recording — stop cleanly.
                self.stopRecording()
            }
            do {
                try micCapture.start(deviceUID: uid) { [weak self] buffer in
                    let level = Self.computeRMS(buffer)
                    self?.transcriber.appendBuffer(buffer)
                    Task { @MainActor [weak self] in
                        guard let self, self.isRecording else { return }
                        self.audioLevel = self.audioLevel * 0.6 + level * 0.4
                        if level > 0.02 { self.rescheduleSilenceTimer() }
                    }
                }
            } catch {
                print("[InputViewModel] Failed to start mic capture: \(error)")
                transcribeError = error.localizedDescription
                isRecording = false
                isTranscribing = false
                transcriber.stopSession()
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        cancelSilenceTimer()
        isRecording = false
        audioLevel = 0
        isTranscribing = true
        if settings.isSystemAudio {
            audioCapture.stop()
        } else {
            micCapture.stop()
        }
        transcriber.stopSession()
        scheduleTranscribingTimeout()
    }

    /// Discard any in-progress recording without waiting for a final transcription result.
    func cancelRecording() {
        sessionGeneration &+= 1
        cancelSilenceTimer()
        cancelTranscribingTimeout()
        pendingSubmit = false
        isRecording = false
        audioLevel = 0
        isTranscribing = false
        recordingBaseText = ""
        audioCapture.stop()
        micCapture.stop()
        transcriber.stopSession()
    }
}
