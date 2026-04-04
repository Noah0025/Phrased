import AVFoundation

protocol ASRProvider: AnyObject {
    var onPartial: ((String) -> Void)? { get set }
    var onFinal: ((String) -> Void)? { get set }

    func warmUp()
    func startSession()
    func stopSession()
    func appendBuffer(_ buffer: AVAudioPCMBuffer)
}
