//
//  Office.swift
//  MOSSU
//
//  Created by Javier Querol on 9/9/22.
//

import Foundation
import CoreLocation
import Cocoa

let allOffices = [plazaAmerica, vlc1, bcn1, mad1, alc1, svq1, mad2, mad3, madridOffice, remote]
let distanceToMatch: CLLocationDistance = 500

let plazaAmerica = Office(location: CLLocation(latitude: 39.469539049320446, longitude: -0.36502215772323376),
                          emoji: ":us:",
                          text: "En Plaza América",
                          ssids:[.piscina, .mdona_1, .mdona_2],
                          barIconImage: NSImage.imageFromEmoji("🇺🇸"))

let vlc1 = Office(location: CLLocation(latitude: 39.45924319299229, longitude: -0.409461898828845),
                  emoji: ":vlc1_bee:",
                  text: "En Colmena VLC1",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "vlc1") ?? .colmenaDefault)

let bcn1 = Office(location: CLLocation(latitude: 41.324591285699036, longitude: 2.1306871470333615),
                  emoji: ":bcn1_bee:",
                  text: "En Colmena BCN1",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "bcn1") ?? .colmenaDefault)

let mad1 = Office(location: CLLocation(latitude: 40.27895254538482, longitude: -3.6830898955727593),
                  emoji: ":mad1_bee:",
                  text: "En Colmena MAD1",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "mad1") ?? .colmenaDefault)

let alc1 = Office(location: CLLocation(latitude: 38.338134188940074, longitude: -0.5323797250531712),
                  emoji: ":alc1_bee:",
                  text: "En Colmena ALC1",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "alc1") ?? .colmenaDefault)

let svq1 = Office(location: CLLocation(latitude: 37.4303284401428, longitude: -5.971076210552222),
                  emoji: ":svq1_bee:",
                  text: "En Colmena SVQ1",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "svq1") ?? .colmenaDefault)

let mad2 = Office(location: CLLocation(latitude: 40.39546191270721, longitude: -3.849994332628127),
                  emoji: ":mad2_bee:",
                  text: "En Colmena MAD2",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "mad2") ?? .colmenaDefault)

let mad3 = Office(location: CLLocation(latitude: 40.367357765499555, longitude: -3.6342218139896008),
                  emoji: ":mad3_bee:",
                  text: "En Colmena MAD3",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "mad3") ?? .colmenaDefault)

let madridOffice = Office(location: CLLocation(latitude: 40.454171947281196, longitude: -3.694558224534412),
                          emoji: ":deciduous_tree:",
                          text: "En la oficina de Madrid",
                          ssids: [.mdona_1, .mdona_2],
                          barIconImage: NSImage.imageFromEmoji("🌳"))

let remote = Office(location: nil,
                    emoji: ":house_with_garden:",
                    text: "En remoto",
                    ssids:[],
                    barIconImage: NSImage.imageFromEmoji("🏡"))

let holiday = Office(location: nil,
                     emoji: ":palm_tree:",
                     text: "En vacaciones",
                     ssids:[],
                     barIconImage: NSImage.imageFromEmoji("🌴"))

struct Office: Equatable {
    var location: CLLocation?
    var emoji: String
    var text: String
    var ssids: [SSID]
    var barIconImage: NSImage
    
    static let unavailableDays: [Int] = [1, 7]
    static let workingHoursStart: Int = 7
    static let workingHoursEnd: Int = 18
    
    enum SSID: String {
        case mdona_1 = "WLAN_PA1"
        case mdona_2 = "WLAN_SA1"
        case piscina = "Piscina_online"
        case remote = ""
    }
    
    static func == (lhs: Office, rhs: Office) -> Bool {
        return lhs.emoji == rhs.emoji
    }
    
    func distance(to location: CLLocation) -> CLLocationDistance {
        guard let currentLocation = self.location else { return 0 }
        return location.distance(from: currentLocation)
    }
    
    static func given(ssid: SSID, currentLocation: CLLocation?) -> Office {
        let possibleOffices = allOffices.filter { $0.ssids.contains(ssid) }
        
        switch possibleOffices.count {
        case 0:
            return remote
        case 1:
            return possibleOffices.first ?? remote
        default:
            guard let currentLocation = currentLocation else { return plazaAmerica }
            let sortedOffices = possibleOffices.filter { $0.location != nil }.sorted(by: currentLocation)
            let closestDistance = sortedOffices.first?.distance(to: currentLocation) ?? distanceToMatch
            if closestDistance < distanceToMatch, let closestOffice = sortedOffices.first {
                return closestOffice
            }
            return remote
        }
    }
    
    static func given(emoji: String) -> Office? {
        return allOffices.filter { $0.emoji == emoji }.first
    }
}
