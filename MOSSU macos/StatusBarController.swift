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
        launchAtLoginEnabled: Bool,
        meetingEnabled: Bool,
        selectedCalendarIdentifier: String?,
        calendarMenuOptions: [(identifier: String, title: String)],
        calendarMenuEnabled: Bool
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
        formatter.doesRelativeDateFormatting = true

        if let composedText = composedText {
            let dateString = formatter.string(from: lastUpdate ?? Date())
            var lastUpdateText = "Última actualización: \(dateString)"

            let weekday = Calendar.current.component(.weekday, from: Date())
            let hour = Calendar.current.component(.hour, from: Date())
            if !SchedulePreferences.shared.isDayEnabled(weekday) {
                let dayName = formatter.weekdaySymbols[weekday - 1]
                lastUpdateText = "Los \(dayName)s no se actualiza Slack"
            } else if !SchedulePreferences.shared.isHourEnabled(hour) {
                lastUpdateText = "Fuera de horario de actualización"
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

        // Scheduling submenu: days and hours
        let schedulingParent = NSMenuItem(title: "⏰ Horario de actualización", action: nil, keyEquivalent: "")
        let schedulingMenu = NSMenu()

        // Days submenu
        let daysItem = NSMenuItem(title: "Días", action: nil, keyEquivalent: "")
        let daysMenu = NSMenu()
        let weekdaysOrder: [Int] = [2,3,4,5,6,7,1] // Mon..Sun
        let weekdaySymbols = formatter.weekdaySymbols // Sunday-first
        for wd in weekdaysOrder {
            let index = wd - 1
            guard let name = weekdaySymbols?[index].capitalized else { return }
            let item = NSMenuItem(title: name, action: #selector(AppDelegate.toggleDay(_:)), keyEquivalent: "")
            item.tag = wd
            item.state = SchedulePreferences.shared.isDayEnabled(wd) ? .on : .off
            daysMenu.addItem(item)
        }
        daysItem.submenu = daysMenu
        schedulingMenu.addItem(daysItem)

        // Hours submenu
        let hoursItem = NSMenuItem(title: "Horas", action: nil, keyEquivalent: "")
        let hoursMenu = NSMenu()
        for hour in 6..<21 {
            let title = String(format: "%02d:00", hour)
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.toggleHour(_:)), keyEquivalent: "")
            item.tag = hour
            item.state = SchedulePreferences.shared.isHourEnabled(hour) ? .on : .off
            hoursMenu.addItem(item)
        }
        hoursItem.submenu = hoursMenu
        schedulingMenu.addItem(hoursItem)

        schedulingParent.submenu = schedulingMenu
        menu.addItem(schedulingParent)

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

        let meetingModeItem = NSMenuItem(
            title: "Observar calendario",
            action: #selector(AppDelegate.toggleMeetingIntegration),
            keyEquivalent: ""
        )
        meetingModeItem.state = meetingEnabled ? .on : .off
        menu.addItem(meetingModeItem)

        if meetingEnabled {
            let calendarParent = NSMenuItem(title: "Calendario observado", action: nil, keyEquivalent: "")
            let calendarMenu = NSMenu()
            let allCalendarsItem = NSMenuItem(
                title: "Todos los calendarios",
                action: #selector(AppDelegate.selectCalendar(_:)),
                keyEquivalent: ""
            )
            allCalendarsItem.state = selectedCalendarIdentifier == nil ? .on : .off
            allCalendarsItem.representedObject = nil
            calendarMenu.addItem(allCalendarsItem)

            if calendarMenuOptions.isEmpty {
                let message = calendarMenuEnabled ? "No hay calendarios disponibles" : "Concede acceso a Calendario"
                let infoItem = NSMenuItem(title: message, action: nil, keyEquivalent: "")
                infoItem.isEnabled = false
                calendarMenu.addItem(infoItem)
            } else {
                for option in calendarMenuOptions {
                    let item = NSMenuItem(
                        title: option.title,
                        action: #selector(AppDelegate.selectCalendar(_:)),
                        keyEquivalent: ""
                    )
                    item.state = option.identifier == selectedCalendarIdentifier ? .on : .off
                    item.representedObject = option.identifier as NSString
                    calendarMenu.addItem(item)
                }
            }

            calendarParent.submenu = calendarMenu
            calendarParent.isEnabled = calendarMenuEnabled
            menu.addItem(calendarParent)
        }

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
