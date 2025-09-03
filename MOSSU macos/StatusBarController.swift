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
        launchAtLoginEnabled: Bool
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
                action: #selector(AppDelegate.showAuth),
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

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        if let composedText = composedText {
            let dateString = formatter.string(from: lastUpdate ?? Date())
            var lastUpdateText = "Actualizado el \(dateString)"

            let weekday = Calendar.current.component(.weekday, from: Date())
            let hour = Calendar.current.component(.hour, from: Date())
            if Office.unavailableDays.contains(weekday) {
                let dayName = formatter.weekdaySymbols[weekday - 1]
                lastUpdateText = "Los \(dayName)s no se actualiza Slack"
            } else if !Office.workingHours.contains(hour) {
                lastUpdateText = "A las \(hour):00 no se actualiza Slack"
            }

            let combinedText = "\(composedText)\n\(lastUpdateText)"
            let attributedString = NSMutableAttributedString(string: combinedText)
            
            let normalFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            let smallFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
            
            let firstLineRange = NSRange(location: 0, length: composedText.count)
            attributedString.addAttribute(.font, value: normalFont, range: firstLineRange)
            
            let dateRange = NSRange(location: composedText.count + 1, length: lastUpdateText.count)
            attributedString.addAttribute(.font, value: smallFont, range: dateRange)
            
            let statusItem = NSMenuItem(
                title: "",
                action: #selector(AppDelegate.showLogs),
                keyEquivalent: ""
            )
            
            statusItem.attributedTitle = attributedString
            menu.addItem(statusItem)
        }

        menu.addItem(NSMenuItem.separator())

        let pausedText =
        (paused || Date() <= holidayEndDate ?? Date().addingTimeInterval(-100000)) ? "▶️ Reanudar actualizaciones" : "⏸️ Pausar actualizaciones"
        let pausedItem = NSMenuItem(
            title: pausedText,
            action: #selector(AppDelegate.pauseOrResumeUpdates),
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
                action: #selector(AppDelegate.setHoliday),
                keyEquivalent: ""
            )
            menu.addItem(holidaysModeItem)
        }

        menu.addItem(NSMenuItem.separator())

        let launchAtLoginItem = NSMenuItem(
            title: "Abrir al iniciar sesión",
            action: #selector(AppDelegate.toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        let updateItem = NSMenuItem(
            title: "Buscar actualizaciones…",
            action: #selector(AppDelegate.checkForUpdates),
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
