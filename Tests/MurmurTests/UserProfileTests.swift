import XCTest
@testable import Murmur

final class UserProfileTests: XCTestCase {
    func test_default_isEmpty() {
        let profile = UserProfile()
        XCTAssertEqual(profile.preferredOutputLanguage, "en")
        XCTAssertEqual(profile.preferredInputLanguage, "zh")
        XCTAssertNil(profile.historySummary)
        XCTAssertTrue(profile.isEmpty)
    }

    func test_encodeDecode_roundTrip() throws {
        var profile = UserProfile()
        profile.historySummary = "User prefers formal English"
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.historySummary, "User prefers formal English")
        XCTAssertFalse(decoded.isEmpty)
    }

    func test_saveAndLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_profile.json")
        defer { try? FileManager.default.removeItem(at: url) }

        var profile = UserProfile()
        profile.historySummary = "test"
        try profile.save(to: url)

        let loaded = try UserProfile.load(from: url)
        XCTAssertEqual(loaded.historySummary, "test")
    }
}
