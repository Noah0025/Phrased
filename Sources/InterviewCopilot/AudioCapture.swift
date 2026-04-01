import Foundation
import AVFoundation
import ScreenCaptureKit

class AudioCapture: NSObject {
    private var stream: SCStream?
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private let lock = NSLock()
    private var _isRunning = false

    var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
        Task {
            await startCapture()
        }
    }

    func stop() {
        Task {
            try? await stream?.stopCapture()
            stream = nil
        }
        lock.withLock { _isRunning = false }
    }

    private func startCapture() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                print("[AudioCapture] No display found")
                return
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 16000
            config.channelCount = 1
            // Minimal video (required even for audio-only capture)
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            try await newStream.startCapture()
            self.stream = newStream
            lock.withLock { self._isRunning = true }
            print("[AudioCapture] Started system audio capture")
        } catch {
            print("[AudioCapture] Failed to start: \(error)")
        }
    }
}

extension AudioCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let pcmBuffer = sampleBuffer.toPCMBuffer() else { return }
        onBuffer?(pcmBuffer)
    }
}

extension CMSampleBuffer {
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }
        let format = AVAudioFormat(streamDescription: asbd)!
        let frameCount = UInt32(CMSampleBufferGetNumSamples(self))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        guard let blockBuffer = CMSampleBufferGetDataBuffer(self) else { return nil }
        var dataPointer: UnsafeMutablePointer<Int8>?
        var length = 0
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let src = dataPointer else { return nil }

        if let floatData = buffer.floatChannelData?.pointee {
            src.withMemoryRebound(to: Float.self, capacity: Int(frameCount)) { srcFloat in
                floatData.update(from: srcFloat, count: Int(frameCount))
            }
        }
        return buffer
    }
}
