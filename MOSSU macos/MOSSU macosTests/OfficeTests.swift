import XCTest
@testable import MOSSU
import CoreLocation

final class OfficeTests: XCTestCase {
    func testGivenSSIDWithNoMatchesReturnsRemote() {
        let office = Office.given(ssid: .remote(ssid: "WiFi_de_casa"), currentLocation: nil)
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
        let office = Office.given(emoji: ":mad1_bee:")
        XCTAssertEqual(office, mad1)
    }

    func testInMeetingUsesMeetingEmojiAndKeepsText() {
        let office = plazaAmerica.inMeeting
        XCTAssertEqual(office.emoji, ":reu+plaza:")
        XCTAssertEqual(office.text, plazaAmerica.text)
    }

    /// Las reuniones seguidas vuelven a publicar la variante que ya está puesta.
    func testInMeetingOnAMeetingVariantChangesNothing() {
        let office = vlc1.inMeeting.inMeeting
        XCTAssertEqual(office.emoji, vlc1.emojiMeeting)
        XCTAssertEqual(office.text, vlc1.text)
    }

    /// Todas las colmenas comparten emoji de reunión: al quitarlo hay que volver a la buena.
    func testWithoutMeetingRecoversTheOfficeOfAMeetingVariant() {
        XCTAssertEqual(mad1.inMeeting.withoutMeeting, mad1)
        XCTAssertEqual(bcn1.inMeeting.withoutMeeting, bcn1)
        XCTAssertEqual(remote.inMeeting.withoutMeeting, remote)
    }

    func testWithoutMeetingLeavesOtherOfficesAsTheyAre() {
        XCTAssertEqual(plazaAmerica.withoutMeeting, plazaAmerica)
        XCTAssertEqual(mercadonaShop.withoutMeeting, mercadonaShop)
        XCTAssertEqual(holiday.withoutMeeting, holiday)
    }
}
