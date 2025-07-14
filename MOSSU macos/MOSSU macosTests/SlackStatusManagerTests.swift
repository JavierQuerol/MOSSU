import XCTest
@testable import MOSSU

final class SlackStatusManagerTests: XCTestCase {
    func testTogglePauseChangesPausedState() {
        let manager = SlackStatusManager()
        XCTAssertFalse(manager.paused)
        manager.togglePause()
        XCTAssertTrue(manager.paused)
        manager.togglePause()
        XCTAssertFalse(manager.paused)
    }

    func testSendHolidaySetsPaused() {
        let manager = SlackStatusManager()
        manager.sendHoliday()
        XCTAssertTrue(manager.paused)
    }
}
