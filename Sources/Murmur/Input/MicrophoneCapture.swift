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
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
        // Use withUnsafeMutablePointer to guarantee pointer lifetime across the call.
        withUnsafeMutablePointer(to: &cfUID) { inputPtr in
            withUnsafeMutablePointer(to: &deviceID) { outputPtr in
                var translation = AudioValueTranslation(
                    mInputData: inputPtr,
                    mInputDataSize: UInt32(MemoryLayout<CFString>.size),
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
