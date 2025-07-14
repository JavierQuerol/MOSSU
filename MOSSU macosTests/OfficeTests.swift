import XCTest
@testable import SSU
import CoreLocation

final class OfficeTests: XCTestCase {
    func testGivenSSIDWithNoMatchesReturnsRemote() {
        let office = Office.given(ssid: .remote, currentLocation: nil)
        XCTAssertEqual(office, remote)
    }

    func testGivenSSIDWithSingleMatchReturnsThatOffice() {
        let office = Office.given(ssid: .piscina, currentLocation: nil)
        XCTAssertEqual(office, plazaAmerica)
    }

    func testGivenSSIDWithMultipleMatchesAndNoLocationReturnsDefault() {
        let office = Office.given(ssid: .mdona_1, currentLocation: nil)
        XCTAssertEqual(office, plazaAmerica)
    }

    func testGivenSSIDWithMultipleMatchesAndLocationReturnsClosestOffice() {
        let location = CLLocation(latitude: 40.279, longitude: -3.683)
        let office = Office.given(ssid: .mdona_1, currentLocation: location)
        XCTAssertEqual(office, mad1)
    }

    func testGivenEmojiReturnsCorrectOffice() {
        let office = Office.given(emoji: ":mad11_bee:")
        XCTAssertEqual(office, mad1)
    }
}
