import Cocoa

class StatusBarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: 18)
        statusItem.button?.title = ""
        statusItem.button?.image = NSImage(named: "AppIcon")
        statusItem.button?.image?.size = NSSize(width: 24, height: 24)
    }

    func update(
        validToken: Bool,
        text: String?,
        office: Office?,
        lastUpdate: Date?,
        name: String,
        paused: Bool,
        holidayEndDate: Date?,
        authSelector: Selector,
        pauseSelector: Selector,
        holidaySelector: Selector,
        updateSelector: Selector
    ) {
        NSApp.setActivationPolicy(.accessory)
        var composedText: String?
        if let office = office {
            statusItem.button?.image = office.barIconImage
            composedText = "\(name) está \(office.text)"
        } else {
            statusItem.button?.image = NSImage(named: "AppIcon")
            composedText = text
        }
        statusItem.button?.title = ""

        let menu = NSMenu()

        if !validToken {
            let status = NSMenuItem(
                title: "🔴 Requiere autorización",
                action: authSelector,
                keyEquivalent: ""
            )
            menu.addItem(status)

            menu.addItem(NSMenuItem.separator())

            menu.addItem(
                NSMenuItem(
                    title: "Salir",
                    action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: ""
                )
            )
            statusItem.menu = menu
            return
        }

        menu.addItem(NSMenuItem.separator())

        if let composedText = composedText {
            let versionItem = NSMenuItem(
                title: composedText,
                action: nil,
                keyEquivalent: ""
            )
            menu.addItem(versionItem)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateString = formatter.string(from: lastUpdate ?? Date())
        var lastUpdateText = "Actualizado el \(dateString)"

        let weekday = Calendar.current.component(.weekday, from: Date())
        let hour = Calendar.current.component(.hour, from: Date())
        if Office.unavailableDays.contains(weekday) {
            let dayName = formatter.weekdaySymbols[weekday - 1]
            lastUpdateText = "Los \(dayName)s no se actualiza Slack"
        } else if hour >= Office.workingHoursEnd || hour < Office.workingHoursStart {
            lastUpdateText =
                "Después de las \(Office.workingHoursEnd):00h no se actualiza Slack"
        }

        let lastUpdate = NSMenuItem(
            title: lastUpdateText,
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(lastUpdate)

        menu.addItem(NSMenuItem.separator())

        let pausedText =
        (paused || Date() <= holidayEndDate ?? Date().addingTimeInterval(-100000)) ? "▶️ Reanudar actualizaciones" : "⏸️ Pausar actualizaciones"
        let pausedItem = NSMenuItem(
            title: pausedText,
            action: pauseSelector,
            keyEquivalent: ""
        )
        menu.addItem(pausedItem)

        if let endDate = holidayEndDate {
            formatter.timeStyle = .none
            let endString = formatter.string(from: endDate)
            let holidayInfo = NSMenuItem(
                title: "🌴 Vacaciones hasta \(endString)",
                action: nil,
                keyEquivalent: ""
            )
            menu.addItem(holidayInfo)
        } else {
            let holidaysModeText = "🌴 Activar modo vacaciones"
            let holidaysModeItem = NSMenuItem(
                title: holidaysModeText,
                action: holidaySelector,
                keyEquivalent: ""
            )
            menu.addItem(holidaysModeItem)
        }

        menu.addItem(NSMenuItem.separator())

        let updateItem = NSMenuItem(
            title: "Buscar actualizaciones…",
            action: updateSelector,
            keyEquivalent: ""
        )
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            NSMenuItem(
                title: "Salir",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: ""
            )
        )
        statusItem.menu = menu
    }
}
