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
    
    func testSendHolidayWithDateStoresEndDate() {
            let manager = SlackStatusManager()
            let date = Date().addingTimeInterval(3600)
            manager.sendHoliday(until: date)
            guard let storedDate = manager.holidayEndDate else {
                XCTFail("holidayEndDate should not be nil")
                return
            }

            XCTAssertEqual(storedDate.timeIntervalSinceReferenceDate, date.timeIntervalSinceReferenceDate, accuracy: 1)
            XCTAssertTrue(manager.paused)
        }
}
