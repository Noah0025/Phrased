import XCTest
@testable import Murmur

final class MurmurSettingsTests: XCTestCase {
    var tmpURL: URL!

    override func setUp() {
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmpURL) }

    func test_defaultSettings_roundTrip() throws {
        let s = MurmurSettings()
        try s.save(to: tmpURL)
        let loaded = try MurmurSettings.load(from: tmpURL)
        XCTAssertEqual(loaded.llmProviderID, s.llmProviderID)
        XCTAssertEqual(loaded.hotkeyKeyCode, s.hotkeyKeyCode)
        XCTAssertEqual(loaded.audioSource, s.audioSource)
    }

    func test_modifiedSettings_persist() throws {
        var s = MurmurSettings()
        s.llmProviderID = "openai"
        s.audioSource = "microphone"
        s.hotkeyKeyCode = 36
        try s.save(to: tmpURL)
        let loaded = try MurmurSettings.load(from: tmpURL)
        XCTAssertEqual(loaded.llmProviderID, "openai")
        XCTAssertEqual(loaded.audioSource, "microphone")
        XCTAssertEqual(loaded.hotkeyKeyCode, 36)
    }
}
