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
    static func imageFromEmoji(_ emoji: String, size: CGFloat = 18) -> NSImage {
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

extension NSStatusItem {
    func configureMenus(validToken: Bool,
                        text: String?,
                        office: Office?,
                        lastUpdate: Date?,
                        name: String,
                        paused: Bool,
                        holidayEndDate: Date?,
                        authSelector: Selector,
                        pauseSelector: Selector,
                        holidaySelector: Selector,
                        updateSelector: Selector) {
        var composedText: String?
        if let office = office {
            button?.image = office.barIconImage
            composedText = "\(name) está \(office.text)"
        } else {
            button?.image = NSImage(named: "AppIcon")
            composedText = text
        }
        button?.title = ""
        
        let menu = NSMenu()
        
        if !validToken {
            let status = NSMenuItem(title: "🔴 Requiere autorización", action: authSelector, keyEquivalent: "")
            menu.addItem(status)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        if let composedText = composedText {
            let versionItem = NSMenuItem(title: composedText, action: nil, keyEquivalent: "")
            menu.addItem(versionItem)
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateString = formatter.string(from: lastUpdate ?? Date())
        let lastUpdate = NSMenuItem(title: "Actualizado el \(dateString)", action: nil , keyEquivalent: "")
        menu.addItem(lastUpdate)
        
        menu.addItem(NSMenuItem.separator())
        
        let pausedText = paused ? "▶️ Reanudar actualizaciones" : "⏸️ Pausar actualizaciones"
        let pausedItem = NSMenuItem(title: pausedText, action: pauseSelector, keyEquivalent: "")
        menu.addItem(pausedItem)

        if let endDate = holidayEndDate, paused {
            let endString = formatter.string(from: endDate)
            let holidayInfo = NSMenuItem(title: "Vacaciones hasta \(endString)", action: nil, keyEquivalent: "")
            menu.addItem(holidayInfo)
        }
        
        let holidaysModeText = "🌴 Activar modo vacaciones"
        let holidaysModeItem = NSMenuItem(title: holidaysModeText, action: holidaySelector, keyEquivalent: "")
        menu.addItem(holidaysModeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let updateItem = NSMenuItem(title: "Buscar actualizaciones…", action: updateSelector, keyEquivalent: "")
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        self.menu = menu
    }
}
