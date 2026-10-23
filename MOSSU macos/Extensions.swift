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
    /// Cualquier error de URLSession es de red: un token inválido no llega así, sino como
    /// respuesta de Slack con `ok: false`. Por eso ninguno de ellos justifica borrar el token.
    func isConnectionProblem() -> Bool {
        (self as NSError).domain == NSURLErrorDomain
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

    /// SF Symbol monocromo para un item de menú. Es plantilla, así que se tiñe como el
    /// texto (también al resaltarlo o deshabilitarlo). Va centrado en un lienzo fijo para
    /// que los títulos queden alineados aunque cada símbolo tenga su propia proporción.
    static func menuSymbol(_ name: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) else { return nil }

        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let scale = min(1, rect.width / symbol.size.width, rect.height / symbol.size.height)
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.draw(in: NSRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            ))
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension String {
    func uppercasedFirst() -> String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }

    /// Trunca por el medio para que quepa en un item de menú.
    func truncatedInMiddle(limit: Int) -> String {
        guard count > limit else { return self }
        let keep = (limit - 1) / 2
        return "\(prefix(keep))…\(suffix(keep))"
    }
}
