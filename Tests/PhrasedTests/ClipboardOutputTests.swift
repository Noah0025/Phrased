import XCTest
@testable import Phrased

final class ClipboardOutputTests: XCTestCase {
    func test_copy_writesStringToClipboard() {
        ClipboardOutput.copy("hello phrased")
        let pasted = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasted, "hello phrased")
    }

    func test_copy_overwritesPreviousContent() {
        ClipboardOutput.copy("first")
        ClipboardOutput.copy("second")
        let pasted = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasted, "second")
    }
}
