import XCTest
@testable import Phrased

final class PhrasedSettingsTests: XCTestCase {
    var tmpURL: URL!

    override func setUp() {
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmpURL) }

    func test_defaultSettings_roundTrip() throws {
        let s = PhrasedSettings()
        try s.save(to: tmpURL)
        let loaded = try PhrasedSettings.load(from: tmpURL)
        XCTAssertEqual(loaded.llmProviderID, s.llmProviderID)
        XCTAssertEqual(loaded.hotkeyKeyCode, s.hotkeyKeyCode)
        XCTAssertEqual(loaded.audioSource, s.audioSource)
    }

    func test_modifiedSettings_persist() throws {
        var s = PhrasedSettings()
        s.llmProviderID = "cloud"
        s.audioSource = "microphone"
        s.hotkeyKeyCode = 36
        try s.save(to: tmpURL)
        let loaded = try PhrasedSettings.load(from: tmpURL)
        XCTAssertEqual(loaded.llmProviderID, "cloud")
        XCTAssertEqual(loaded.audioSource, "microphone")
        XCTAssertEqual(loaded.hotkeyKeyCode, 36)
    }
}
