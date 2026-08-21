import XCTest
@testable import MOSSU

final class SlackStatusManagerTests: XCTestCase {
    /// `paused` y la fecha de vuelta se persisten, así que hay que dejar limpio el terreno
    /// entre tests: si no, el estado de uno decide el resultado del siguiente.
    override func setUp() {
        super.setUp()
        clearStoredState()
    }

    override func tearDown() {
        clearStoredState()
        super.tearDown()
    }

    private func clearStoredState() {
        UserDefaults.standard.removeObject(forKey: "paused")
        UserDefaults.standard.removeObject(forKey: "holidayEndDate")
    }

    private func day(offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date())!
    }

    func testTogglePauseChangesPausedState() {
        let manager = SlackStatusManager()
        XCTAssertFalse(manager.paused)
        manager.togglePause()
        XCTAssertTrue(manager.paused)
        manager.togglePause()
        XCTAssertFalse(manager.paused)
    }

    func testSendHolidayStoresStartOfReturnDay() {
        let manager = SlackStatusManager()
        let returnDate = day(offset: 3)

        manager.sendHoliday(until: returnDate)

        XCTAssertEqual(manager.holidayEndDate, Calendar.current.startOfDay(for: returnDate))
        XCTAssertEqual(manager.activeHolidayEndDate, manager.holidayEndDate)
        XCTAssertTrue(manager.isOnHoliday)
        XCTAssertTrue(manager.paused)
    }

    func testSendHolidayRejectsReturnDateAlreadyPassed() {
        let manager = SlackStatusManager()

        manager.sendHoliday(until: day(offset: -1))

        XCTAssertNil(manager.holidayEndDate)
        XCTAssertFalse(manager.paused)
    }

    /// Volver hoy no son vacaciones: las 00:00 de hoy ya han pasado.
    func testSendHolidayRejectsToday() {
        let manager = SlackStatusManager()

        manager.sendHoliday(until: Date())

        XCTAssertNil(manager.holidayEndDate)
        XCTAssertFalse(manager.paused)
    }

    func testExpiredHolidayIsClearedOnLaunch() {
        UserDefaults.standard.set(day(offset: -2), forKey: "holidayEndDate")
        UserDefaults.standard.set(true, forKey: "paused")

        let manager = SlackStatusManager()

        XCTAssertNil(manager.holidayEndDate)
        XCTAssertNil(manager.activeHolidayEndDate)
        XCTAssertFalse(manager.isOnHoliday)
        XCTAssertFalse(manager.paused)
        XCTAssertNil(UserDefaults.standard.value(forKey: "holidayEndDate"))
    }

    func testActiveHolidaySurvivesRelaunch() {
        let returnDate = Calendar.current.startOfDay(for: day(offset: 2))
        UserDefaults.standard.set(returnDate, forKey: "holidayEndDate")
        UserDefaults.standard.set(true, forKey: "paused")

        let manager = SlackStatusManager()

        XCTAssertEqual(manager.activeHolidayEndDate, returnDate)
        XCTAssertTrue(manager.isOnHoliday)
        XCTAssertTrue(manager.paused)
    }

    func testExpireHolidayIfNeededKeepsHolidayStillRunning() {
        let manager = SlackStatusManager()
        manager.sendHoliday(until: day(offset: 3))

        XCTAssertFalse(manager.expireHolidayIfNeeded())
        XCTAssertNotNil(manager.activeHolidayEndDate)
        XCTAssertTrue(manager.paused)
    }

    func testResumingUpdatesClearsHoliday() {
        let manager = SlackStatusManager()
        manager.sendHoliday(until: day(offset: 3))

        manager.togglePause()

        XCTAssertNil(manager.holidayEndDate)
        XCTAssertNil(manager.activeHolidayEndDate)
        XCTAssertFalse(manager.paused)
    }

    /// Vacaciones guardadas por una versión que no persistía la pausa: al arrancar tienen
    /// que quedar en pausa igualmente, o el menú diría que MOSSU sigue actualizando.
    func testHolidayStoredWithoutPauseIsPausedOnLaunch() {
        UserDefaults.standard.set(Calendar.current.startOfDay(for: day(offset: 2)), forKey: "holidayEndDate")

        let manager = SlackStatusManager()

        XCTAssertTrue(manager.paused)
        XCTAssertTrue(manager.isOnHoliday)
    }

    /// El botón "Cancelar" de Ajustes pasaba por `togglePause`, que sin pausa guardada
    /// acababa pausando en vez de cancelar.
    func testCancelHolidayWorksWhenPauseWasNotStored() {
        UserDefaults.standard.set(Calendar.current.startOfDay(for: day(offset: 2)), forKey: "holidayEndDate")
        let manager = SlackStatusManager()

        let model = SettingsModel.shared
        model.configure(slackManager: manager,
                        launchAtLoginManager: LaunchAtLoginManager(),
                        checkForUpdates: {},
                        showLogs: {},
                        startHoliday: { _ in })

        model.cancelHoliday()

        XCTAssertNil(manager.holidayEndDate)
        XCTAssertNil(model.holidayEndDate)
        XCTAssertFalse(manager.paused)
    }
}
