//
//  Office.swift
//  MOSSU
//
//  Created by Javier Querol on 9/9/22.
//

import Foundation
import CoreLocation
import Cocoa

let allOffices = [plazaAmerica, vlc1, bcn1, mad1, alc1, svq1, mad2, mad3, madridOffice, remote, mercadonaShop]
let distanceToMatch: CLLocationDistance = 500

let plazaAmerica = Office(location: CLLocation(latitude: 39.469539049320446, longitude: -0.36502215772323376),
                          emoji: ":us:",
                          text: "en Plaza América",
                          ssids:[.piscina, .mdona_1, .mdona_2],
                          barIconImage: NSImage.imageFromEmoji("🇺🇸"),
                          emojiMeeting: ":reu+plaza:",
                          barIconImageMeeting: NSImage(named: "reu_plaza") ?? NSImage.imageFromEmoji("🇺🇸"))

let vlc1 = Office(location: CLLocation(latitude: 39.45924319299229, longitude: -0.409461898828845),
                  emoji: ":vlc1_bee:",
                  text: "en Colmena VLC1",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "vlc1") ?? .colmenaDefault,
                  emojiMeeting: ":reu+colmena:",
                  barIconImageMeeting: NSImage(named: "reu_colmena") ?? .colmenaDefault)

let bcn1 = Office(location: CLLocation(latitude: 41.324591285699036, longitude: 2.1306871470333615),
                  emoji: ":bcn1_bee:",
                  text: "en Colmena BCN1",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "bcn1") ?? .colmenaDefault,
                  emojiMeeting: ":reu+colmena:",
                  barIconImageMeeting: NSImage(named: "reu_colmena") ?? .colmenaDefault)

let mad1 = Office(location: CLLocation(latitude: 40.27895254538482, longitude: -3.6830898955727593),
                  emoji: ":mad1_bee:",
                  text: "en Colmena MAD1",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "mad1") ?? .colmenaDefault,
                  emojiMeeting: ":reu+colmena:",
                  barIconImageMeeting: NSImage(named: "reu_colmena") ?? .colmenaDefault)

let alc1 = Office(location: CLLocation(latitude: 38.338134188940074, longitude: -0.5323797250531712),
                  emoji: ":alc1_bee:",
                  text: "en Colmena ALC1",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "alc1") ?? .colmenaDefault,
                  emojiMeeting: ":reu+colmena:",
                  barIconImageMeeting: NSImage(named: "reu_colmena") ?? .colmenaDefault)

let svq1 = Office(location: CLLocation(latitude: 37.4303284401428, longitude: -5.971076210552222),
                  emoji: ":svq1_bee:",
                  text: "en Colmena SVQ1",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "svq1") ?? .colmenaDefault,
                  emojiMeeting: ":reu+colmena:",
                  barIconImageMeeting: NSImage(named: "reu_colmena") ?? .colmenaDefault)

let mad2 = Office(location: CLLocation(latitude: 40.39546191270721, longitude: -3.849994332628127),
                  emoji: ":mad2_bee:",
                  text: "en Colmena MAD2",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "mad2") ?? .colmenaDefault,
                  emojiMeeting: ":reu+colmena:",
                  barIconImageMeeting: NSImage(named: "reu_colmena") ?? .colmenaDefault)

let mad3 = Office(location: CLLocation(latitude: 40.367357765499555, longitude: -3.6342218139896008),
                  emoji: ":mad3_bee:",
                  text: "en Colmena MAD3",
                  ssids:[.mdona_1, .mdona_2],
                  barIconImage: NSImage(named: "mad3") ?? .colmenaDefault,
                  emojiMeeting: ":reu+colmena:",
                  barIconImageMeeting: NSImage(named: "reu_colmena") ?? .colmenaDefault)

let madridOffice = Office(location: CLLocation(latitude: 40.454171947281196, longitude: -3.694558224534412),
                          emoji: ":deciduous_tree:",
                          text: "en la oficina de Madrid",
                          ssids: [.mdona_1, .mdona_2],
                          barIconImage: NSImage.imageFromEmoji("🌳"),
                          emojiMeeting: ":reu_mad_office:",
                          barIconImageMeeting: NSImage(named: "reu_mad_office") ?? NSImage.imageFromEmoji("🌳"))

let mercadonaShop = Office(location: nil,
                           emoji: ":mercadona:",
                           text: "en tienda",
                           ssids: [.mdona_1, .mdona_2],
                           barIconImage: NSImage(named: "mercadona") ?? .colmenaDefault,
                           emojiMeeting: ":mercadona:",
                           barIconImageMeeting: NSImage(named: "mercadona") ?? .colmenaDefault)

let remote = Office(location: nil,
                    emoji: ":house_with_garden:",
                    text: "en remoto",
                    ssids:[],
                    barIconImage: NSImage.imageFromEmoji("🏡"),
                    emojiMeeting: ":reu+home:",
                    barIconImageMeeting: NSImage(named: "reu_home") ?? NSImage.imageFromEmoji("🏡"))

let holiday = Office(location: nil,
                     emoji: ":palm_tree:",
                     text: "en vacaciones",
                     ssids:[],
                     barIconImage: NSImage.imageFromEmoji("🌴"),
                     emojiMeeting: ":palm_tree:",
                     barIconImageMeeting: NSImage.imageFromEmoji("🌴"))

struct Office: Equatable {
    var location: CLLocation?
    var emoji: String
    var text: String
    var ssids: [SSID]
    var barIconImage: NSImage
    var emojiMeeting: String
    var barIconImageMeeting: NSImage
    
    static let unavailableDays: [Int] = [1, 7]
    static let workingHours: [Int] = [8,9,10,11,12,15,16,17,18]
    
    enum SSID: Equatable {
        case mdona_1
        case mdona_2
        case piscina
        case remote(ssid: String)
        
        var rawValue: String {
            switch self {
            case .mdona_1:
                return "WLAN_PA1"
            case .mdona_2:
                return "WLAN_SA1"
            case .piscina:
                return "Piscina_online"
            case .remote(let ssid):
                return ssid
            }
        }
        
        init?(rawValue: String) {
            switch rawValue {
            case "WLAN_PA1":
                self = .mdona_1
            case "WLAN_SA1":
                self = .mdona_2
            case "Piscina_online":
                self = .piscina
            default:
                self = .remote(ssid: rawValue)
            }
        }
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
            return mercadonaShop
        }
    }
    
    static func given(emoji: String) -> Office? {
        return allOffices.filter { $0.emoji == emoji }.first
    }
}
