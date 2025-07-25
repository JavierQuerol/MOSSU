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
        return Office.SSID(rawValue: string) ?? remote(ssid: string)
    }
}

extension NSScreen {
    static func hasActiveDisplay() -> Bool {
        // Verificar si hay pantallas disponibles y si alguna está activa
        guard !NSScreen.screens.isEmpty else { return false }
        
        // Obtener la pantalla principal
        guard let mainScreen = NSScreen.main else { return false }
        
        // Verificar si la pantalla principal está activa usando Core Graphics
        let mainDisplayID = mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        
        // Una pantalla está activa si no está en modo sleep/closed
        return CGDisplayIsActive(mainDisplayID) != 0
    }
}

extension Error {
    func isConnectionProblem() -> Bool {
        let nSError = self as NSError
        return nSError.code == -1009
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
    
    static let colmenaDefault = imageFromEmoji("🐝")
}

extension String {
    func uppercasedFirst() -> String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
