import XCTest
@testable import Pendel

final class CountdownTests: XCTestCase {
    func testWordingBySize() {
        XCTAssertEqual(CountdownView.text(-5), "jetzt")
        XCTAssertEqual(CountdownView.text(0), "0:00")
        XCTAssertEqual(CountdownView.text(95), "1:35")
        XCTAssertEqual(CountdownView.text(599), "9:59")
        XCTAssertEqual(CountdownView.text(600), "10 min")
        XCTAssertEqual(CountdownView.text(3600 + 300), "1:05 h")
    }

    func testColourWarnsAtFiveMinutes() {
        XCTAssertEqual(CountdownView.tint(900), Theme.accent)
        XCTAssertEqual(CountdownView.tint(299), .orange)
        XCTAssertEqual(CountdownView.tint(-1), .red)
    }
}
