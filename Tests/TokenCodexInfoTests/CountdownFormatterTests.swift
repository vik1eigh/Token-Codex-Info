import XCTest
@testable import TokenCodexInfoCore

final class CountdownFormatterTests: XCTestCase {
    func testMenuClockFormatting() {
        XCTAssertEqual(CountdownFormatter.menuClock(seconds: 2 * 60 * 60 + 14 * 60), "2:14")
        XCTAssertEqual(CountdownFormatter.menuClock(seconds: 5 * 60), "0:05")
        XCTAssertEqual(CountdownFormatter.menuClock(seconds: -10), "0:00")
    }

    func testMenuTitleRendersExpectedReference() {
        XCTAssertEqual(MenuBarTitleFormatter.string(percent: 97, countdownSeconds: 2 * 60 * 60 + 14 * 60), "97% · 2:14")
    }

    func testMenuTitleUsesPlaceholderWhenResetIsUnknown() {
        XCTAssertEqual(MenuBarTitleFormatter.string(percent: 83, resetAt: nil, now: Date()), "83% · --")
    }

    func testMenuTitleUsesPlaceholderWhenResetAlreadyPassed() {
        let now = Date(timeIntervalSince1970: 20_000)
        let expiredReset = Date(timeIntervalSince1970: 19_999)
        XCTAssertEqual(MenuBarTitleFormatter.string(percent: 39, resetAt: expiredReset, now: now), "39% · --")
    }

    func testMenuTitlePartsRenderClockSeparator() {
        let parts = MenuBarTitleFormatter.parts(percent: 97, countdownSeconds: 2 * 60 * 60 + 14 * 60)
        XCTAssertEqual(parts.colon, ":")
        XCTAssertEqual(parts.stringValue, "97% · 2:14")
    }

    func testResetDateUsesReferenceColumnOrder() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026
        components.month = 7
        components.day = 11
        components.hour = 12

        let date = try XCTUnwrap(components.date)
        XCTAssertEqual(ResetDateFormatter.menuDate(date), "11 Jul")
    }
}
