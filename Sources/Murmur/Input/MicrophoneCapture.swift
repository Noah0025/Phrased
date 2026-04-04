import AVFoundation
import AudioToolbox
import CoreAudio

/// Captures a specific microphone input via AVAudioEngine.
/// Outputs 16 kHz mono Float32 PCM buffers — same format as AudioCapture.
///
/// `start()`, `stop()`, and all mutable state must be accessed from the main actor.
/// The tap callback fires on AVAudioEngine's internal thread and accesses only
/// immutable captures — no actor-isolated state is touched from background threads.
class MicrophoneCapture {
    @MainActor private var engine: AVAudioEngine?
    @MainActor private(set) var isRunning = false

    /// Called on the main thread when the underlying audio engine loses its device
    /// configuration (e.g. Bluetooth headset disconnects mid-recording).
    @MainActor var onDeviceLost: (() -> Void)?

    // Known-valid compile-time constants — force-unwrap is intentional.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// - Parameter deviceUID: `AVCaptureDevice.uniqueID` for the desired
    ///   microphone.  Pass `nil` to use the system default input device.
    /// - Throws: If the AVAudioEngine fails to start.
    @MainActor
    func start(deviceUID: String? = nil, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        // Tear down any existing session before starting a new one.
        if isRunning { stop() }

        let engine = AVAudioEngine()
        self.engine = engine

        // Must set device before querying outputFormat — format depends on the device.
        if let uid = deviceUID {
            Self.setInputDevice(uid: uid, on: engine)
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // Build the converter once for this session and capture it by value in the
        // tap closure — this avoids accessing any actor-isolated property from the
        // background thread on which AVAudioEngine fires the tap.
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw MicCaptureError.converterUnavailable
        }
        let targetFormat = self.targetFormat  // capture by value

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, using: converter, to: targetFormat) else { return }
            onBuffer(converted)
        }

        // Observe device configuration changes (e.g. Bluetooth disconnect).
        // AVFoundation posts AVAudioEngineConfigurationChange on the main thread.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(engineConfigurationChanged),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )

        do {
            try engine.start()
            isRunning = true
        } catch {
            // Clean up before propagating so the engine can be safely deallocated.
            NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)
            engine.inputNode.removeTap(onBus: 0)
            self.engine = nil
            isRunning = false
            throw error
        }
    }

    @MainActor
    func stop() {
        guard let engine else { return }
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        isRunning = false
    }

    // MARK: - Private helpers

    @objc private func engineConfigurationChanged(_ notification: Notification) {
        // AVFoundation documents that AVAudioEngineConfigurationChange fires on the main thread.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stop()
            self.onDeviceLost?()
        }
    }

    /// Pure conversion helper — no instance state accessed, safe to call from any thread.
    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )
        guard frameCapacity > 0,
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
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
        let status = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            // Device set failed (e.g. output-only device); engine will use system default.
            print("[MicrophoneCapture] AudioUnitSetProperty failed for uid \(uid), OSStatus \(status)")
        }
    }

    /// Returns the `AudioDeviceID` for the given UID, or `nil` if not found.
    private static func audioDeviceID(for uid: String) -> AudioDeviceID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var cfUID = uid as CFString
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // mInputData must point to a CFStringRef (an opaque 8-byte pointer), not the
        // string contents — MemoryLayout<CFStringRef>.size == sizeof(void*) == 8.
        var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
        withUnsafeMutablePointer(to: &cfUID) { inputPtr in
            withUnsafeMutablePointer(to: &deviceID) { outputPtr in
                var translation = AudioValueTranslation(
                    mInputData: inputPtr,
                    mInputDataSize: UInt32(MemoryLayout<CFString>.size), // CFString is a reference type: size == sizeof(void*) == 8
                    mOutputData: outputPtr,
                    mOutputDataSize: UInt32(MemoryLayout<AudioObjectID>.size)
                )
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &translation
                )
            }
        }
        return deviceID != kAudioObjectUnknown ? deviceID : nil
    }
}

enum MicCaptureError: Error {
    case converterUnavailable
}
