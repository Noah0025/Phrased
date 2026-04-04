# Audio Source Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the top-level audio source toggle button with a right-click context menu on the mic button, and enumerate all real audio input devices (built-in, AirPods, Bluetooth headsets) instead of just "microphone" vs "system audio".

**Architecture:** `AudioDeviceManager` enumerates `AVCaptureDevice` audio inputs and publishes a reactive device list. `MicrophoneCapture` gains a `deviceUID` parameter to target a specific device via Core Audio's `AudioUnitSetProperty`. `InputViewModel` wires the two together and exposes a `selectAudioSource()` action. The mic button in `MurmurView` gets a `.contextMenu` using SwiftUI `Picker(.inline)` for clean checkmark rendering; the old `audioSourceButton` is removed.

**Tech Stack:** Swift, AVFoundation (device enumeration + capture), CoreAudio + AudioToolbox (device UID→ID translation + AudioUnit property), SwiftUI `.contextMenu` + `Picker(.inline)`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Sources/Murmur/Input/AudioDeviceManager.swift` | `AudioDevice` model + live enumeration + change notifications |
| Modify | `Sources/Murmur/Input/MicrophoneCapture.swift` | Accept `deviceUID` param, set device on AVAudioEngine |
| Modify | `Sources/Murmur/Input/InputWindow.swift` | `InputViewModel`: host manager, expose devices, `selectAudioSource()` |
| Modify | `Sources/Murmur/Confirm/ConfirmWindow.swift` | `MurmurView`: context menu on mic button, remove `audioSourceButton` |

---

## Task 1: AudioDevice model + AudioDeviceManager

**Files:**
- Create: `Sources/Murmur/Input/AudioDeviceManager.swift`

- [ ] **Step 1: Write the file**

```swift
import AVFoundation

// MARK: - AudioDevice

struct AudioDevice: Identifiable, Equatable {
    let id: String          // AVCaptureDevice.uniqueID  or  "systemAudio"
    let name: String
    let isSystemAudio: Bool
}

// MARK: - AudioDeviceManager

/// Enumerates available audio input devices and publishes updates when
/// devices are connected or disconnected (Bluetooth, USB, built-in).
class AudioDeviceManager: ObservableObject {

    static let systemAudio = AudioDevice(
        id: "systemAudio",
        name: "系统音频",
        isSystemAudio: true
    )

    @Published private(set) var devices: [AudioDevice] = []

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceListChanged),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceListChanged),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Rebuild the device list. Always puts "系统音频" first.
    func refresh() {
        let mics = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices.map {
            AudioDevice(id: $0.uniqueID, name: $0.localizedName, isSystemAudio: false)
        }
        devices = [Self.systemAudio] + mics
    }

    /// Returns `true` if `id` is still present in the current device list.
    func contains(id: String) -> Bool {
        devices.contains { $0.id == id }
    }

    @objc private func deviceListChanged() {
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }
}
```

- [ ] **Step 2: Build to verify no errors**

```bash
cd ~/Projects/InterviewCopilot && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/InterviewCopilot
git add Sources/Murmur/Input/AudioDeviceManager.swift
git commit -m "feat: add AudioDevice model and AudioDeviceManager"
```

---

## Task 2: MicrophoneCapture — specific device support

**Files:**
- Modify: `Sources/Murmur/Input/MicrophoneCapture.swift`

`AVAudioEngine.inputNode` uses the system default input device unless overridden.
To target a specific device, obtain its `AudioDeviceID` from the UID string via
`kAudioHardwarePropertyTranslateUIDToDevice`, then push it onto the node's
underlying `AudioUnit` with `kAudioOutputUnitProperty_CurrentDevice` *before*
calling `outputFormat(forBus:)` (which reads the device's native format).

- [ ] **Step 1: Replace the entire file**

```swift
import AVFoundation
import AudioToolbox
import CoreAudio

/// Captures a specific microphone input via AVAudioEngine.
/// Outputs 16 kHz mono Float32 PCM buffers — same format as AudioCapture.
class MicrophoneCapture {
    private var engine: AVAudioEngine?
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private(set) var isRunning = false

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// - Parameter deviceUID: `AVCaptureDevice.uniqueID` for the desired
    ///   microphone.  Pass `nil` to use the system default input device.
    func start(deviceUID: String? = nil, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
        let engine = AVAudioEngine()
        self.engine = engine

        // Must set device before querying outputFormat — format depends on the device.
        if let uid = deviceUID {
            Self.setInputDevice(uid: uid, on: engine)
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converted = self.convert(buffer, to: self.targetFormat) else { return }
            self.onBuffer?(converted)
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
    }

    // MARK: - Private helpers

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            outStatus.pointee = .haveData
            consumed = true
            return buffer
        }
        return error == nil ? out : nil
    }

    /// Translates an AVCaptureDevice UID to the Core Audio device ID, then
    /// pushes it onto the input node's AudioUnit before the engine starts.
    private static func setInputDevice(uid: String, on engine: AVAudioEngine) {
        guard let deviceID = audioDeviceID(for: uid),
              let au = engine.inputNode.audioUnit else { return }
        var id = deviceID
        AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    /// Returns the `AudioDeviceID` for the given UID, or `nil` if not found.
    private static func audioDeviceID(for uid: String) -> AudioDeviceID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var cfUID = uid as CFString
        var translation = AudioValueTranslation(
            mInputData: &cfUID,
            mInputDataSize: UInt32(MemoryLayout<CFString>.size),
            mOutputData: &deviceID,
            mOutputDataSize: UInt32(MemoryLayout<AudioObjectID>.size)
        )
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &translation
        )
        return deviceID != kAudioObjectUnknown ? deviceID : nil
    }
}
```

- [ ] **Step 2: Build**

```bash
cd ~/Projects/InterviewCopilot && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/InterviewCopilot
git add Sources/Murmur/Input/MicrophoneCapture.swift
git commit -m "feat: MicrophoneCapture accepts deviceUID for specific input device"
```

---

## Task 3: InputViewModel — integrate AudioDeviceManager

**Files:**
- Modify: `Sources/Murmur/Input/InputWindow.swift`

Changes:
1. `settings` → `@Published var settings` so the Picker binding re-renders on change.
2. Add `AudioDeviceManager` and forward its `devices` as `@Published var availableDevices`.
3. Add `selectAudioSource(_:)` — updates `settings.audioSource`, saves to disk, falls back to "systemAudio" if selected device disappears.
4. In `startRecording()`, pass `deviceUID` to `micCapture.start(deviceUID:)`.

- [ ] **Step 1: Apply changes to `InputViewModel`**

Add `import Combine` at the top of `InputWindow.swift` (after `import AppKit`).

Then replace the `InputViewModel` class (lines 5–96) with:

```swift
@MainActor
class InputViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var editorHeight: CGFloat = 22
    @Published var isRecording: Bool = false
    @Published var isTranscribing: Bool = false
    @Published var selectedTemplate: PromptTemplate = PromptTemplate.builtins[0]
    @Published var allTemplates: [PromptTemplate] = PromptTemplate.builtins
    @Published var contextAppName: String? = nil
    @Published var settings: MurmurSettings = MurmurSettings()
    @Published var availableDevices: [AudioDevice] = []

    var onSubmit: ((String, PromptTemplate) -> Void)?

    private let audioCapture = AudioCapture()
    private let micCapture = MicrophoneCapture()
    private let deviceManager = AudioDeviceManager()
    private var transcriber: ASRProvider
    private var pendingSubmit = false
    var vocabularyStore: VocabularyStore = VocabularyStore()

    init(transcriber: ASRProvider = WhisperTranscriber()) {
        self.transcriber = transcriber
        // Forward device list from manager
        availableDevices = deviceManager.devices
        deviceManager.$devices
            .receive(on: DispatchQueue.main)
            .assign(to: &$availableDevices)

        transcriber.onFinal = { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isTranscribing = false
                self.inputText = text
                if self.pendingSubmit {
                    self.pendingSubmit = false
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.onSubmit?(text, self.selectedTemplate)
                    }
                }
            }
        }
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

    /// Sets the active audio source and persists the preference.
    /// If the chosen device is no longer available, falls back to "systemAudio".
    func selectAudioSource(_ id: String) {
        let resolvedID = deviceManager.contains(id: id) ? id : "systemAudio"
        settings.audioSource = resolvedID
        try? settings.save()
    }

    func updateASRProvider(_ asr: ASRProvider) {
        transcriber = asr
    }

    func warmUpTranscriber() {
        transcriber.warmUp()
    }

    func toggleRecording() {
        isRecording ? stopRecordingManually() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        inputText = ""
        transcriber.startSession()
        if settings.audioSource == "systemAudio" {
            audioCapture.start { [weak self] buffer in
                self?.transcriber.appendBuffer(buffer)
            }
        } else {
            let uid = settings.audioSource
            micCapture.start(deviceUID: uid) { [weak self] buffer in
                self?.transcriber.appendBuffer(buffer)
            }
        }
    }

    private func stopRecordingManually() {
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        isTranscribing = true
        audioCapture.stop()
        micCapture.stop()
        transcriber.stopSession()
    }
}
```

- [ ] **Step 2: Remove the now-unused `var settings` line from `InputViewModel`**

The old `var settings: MurmurSettings = MurmurSettings()` (non-published) is replaced by `@Published var settings` above. Verify the file has no duplicate `settings` declaration:

```bash
grep -n "var settings" ~/Projects/InterviewCopilot/Sources/Murmur/Input/InputWindow.swift
```
Expected: exactly one line, `@Published var settings: MurmurSettings = MurmurSettings()`.

- [ ] **Step 3: Build**

```bash
cd ~/Projects/InterviewCopilot && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/InterviewCopilot
git add Sources/Murmur/Input/InputWindow.swift
git commit -m "feat: InputViewModel uses AudioDeviceManager, exposes availableDevices and selectAudioSource"
```

---

## Task 4: MurmurView — context menu + remove audioSourceButton

**Files:**
- Modify: `Sources/Murmur/Confirm/ConfirmWindow.swift`

Two changes:
1. Add `.contextMenu` with an inline `Picker` to `micButton`. SwiftUI renders an inline picker inside a context menu as a list of NSMenuItems with checkmarks — no custom drawing needed.
2. Remove `audioSourceButton` from `inputBar` and delete its `var audioSourceButton` computed property.

- [ ] **Step 1: Add context menu to `micButton`**

Find the `micButton` computed property and replace it:

```swift
private var micButton: some View {
    Button {
        inputVM.toggleRecording()
    } label: {
        Image(systemName: inputVM.isRecording ? "stop.fill" : "waveform")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(inputVM.isRecording ? .red : .secondary)
            .frame(width: 28, height: 28)
    }
    .buttonStyle(.plain)
    .help(inputVM.isRecording ? "停止录音" : "开始录音（右键选择来源）")
    .onChange(of: inputVM.isRecording) { pulsing = $0 }
    .contextMenu {
        Picker("音频来源", selection: Binding(
            get: { inputVM.settings.audioSource },
            set: { inputVM.selectAudioSource($0) }
        )) {
            ForEach(inputVM.availableDevices) { device in
                Label(device.name,
                      systemImage: device.isSystemAudio ? "desktopcomputer" : "mic")
                    .tag(device.id)
            }
        }
        .pickerStyle(.inline)
    }
}
```

- [ ] **Step 2: Remove `audioSourceButton` from `inputBar`**

Find `inputBar` and remove the `audioSourceButton` line:

```swift
// BEFORE
private var inputBar: some View {
    HStack(alignment: .bottom, spacing: 0) {
        micButton
            .padding(.leading, 10)
            .padding(.bottom, 9)
        inputArea
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        stylePicker
            .padding(.bottom, 7)
        audioSourceButton
            .padding(.bottom, 7)
        Spacer().frame(width: 12)
        submitButton
            .padding(.trailing, 10)
            .padding(.bottom, 9)
    }
}

// AFTER
private var inputBar: some View {
    HStack(alignment: .bottom, spacing: 0) {
        micButton
            .padding(.leading, 10)
            .padding(.bottom, 9)
        inputArea
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        stylePicker
            .padding(.bottom, 7)
        Spacer().frame(width: 12)
        submitButton
            .padding(.trailing, 10)
            .padding(.bottom, 9)
    }
}
```

- [ ] **Step 3: Delete the `audioSourceButton` computed property**

Remove the entire `// MARK: Audio source button` section and its `private var audioSourceButton: some View { ... }` block.

- [ ] **Step 4: Build**

```bash
cd ~/Projects/InterviewCopilot && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 5: Package and smoke-test**

```bash
cd ~/Projects/InterviewCopilot && make package 2>&1 | tail -4
pkill -x Murmur 2>/dev/null; sleep 0.5; open Murmur.app
```

Manual checks:
- Right-click mic button → context menu shows "系统音频" + available mics with checkmark on active
- Selecting a mic persists after relaunching (settings saved to disk)
- Recording with each source type works
- Connecting/disconnecting a Bluetooth headset updates the list (without restarting)

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/InterviewCopilot
git add Sources/Murmur/Confirm/ConfirmWindow.swift
git commit -m "feat: mic button context menu for audio source, remove top-level toggle button"
```
