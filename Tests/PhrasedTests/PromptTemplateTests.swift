import XCTest
@testable import Phrased

final class PromptTemplateTests: XCTestCase {
    func test_builtins_notEmpty() {
        XCTAssertFalse(PromptTemplate.builtins.isEmpty)
    }

    func test_autoTemplate_hasNilInstruction() {
        let auto = PromptTemplate.builtins.first { $0.id == "auto" }
        XCTAssertNotNil(auto)
        XCTAssertNil(auto?.promptInstruction)
    }

    func test_customTemplate_roundTrip() throws {
        let t = PromptTemplate(id: "t1", name: "Test", promptInstruction: "Be brief.")
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(PromptTemplate.self, from: data)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.promptInstruction, "Be brief.")
    }

    func test_allBuiltinsHaveUniqueIDs() {
        let ids = PromptTemplate.builtins.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
