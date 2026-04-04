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
