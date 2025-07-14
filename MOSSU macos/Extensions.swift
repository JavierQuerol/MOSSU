//
//  Extensions.swift
//  MOSSU
//
//  Created by Javier Querol on 14/9/22.
//

import Foundation
import CoreLocation
import AppKit
import CoreWLAN

extension Array where Element == Office {
    func sorted(by location: CLLocation) -> [Office] {
        return sorted(by: { $0.distance(to: location) < $1.distance(to: location) })
    }
}

extension Office.SSID {
    static func current() -> Office.SSID {
        let string = CWWiFiClient.shared().interfaces()?.compactMap { $0.ssid() }.first ?? ""
        return Office.SSID(rawValue: string) ?? remote
    }
}

extension NSScreen {
    static func hasActiveDisplay() -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        if CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success {
            return count != 0
        }
        return false
    }
}

extension NSImage {
    static func imageFromEmoji(_ emoji: String, size: CGFloat = 14) -> NSImage {
        let font = NSFont.systemFont(ofSize: size)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let attributedString = NSAttributedString(string: emoji, attributes: attributes)
        let imageSize = attributedString.size()

        let image = NSImage(size: imageSize)
        image.lockFocus()
        attributedString.draw(at: .zero)
        image.unlockFocus()

        return image
    }
}
