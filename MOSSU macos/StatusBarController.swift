import Cocoa
import KeyboardShortcuts

/// Refresca el item de LAPS justo antes de que el menú se despliegue.
private final class MenuRefresher: NSObject, NSMenuDelegate {
    private let onOpen: () -> Void

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
    }

    func menuWillOpen(_ menu: NSMenu) {
        onOpen()
    }
}

class StatusBarController {
    private let statusItem: NSStatusItem
    private var lapsMenuItem: NSMenuItem?
    private lazy var menuRefresher = MenuRefresher { [weak self] in
        guard let item = self?.lapsMenuItem else { return }
        self?.configureLAPSItem(item)
    }

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: 18)
        statusItem.button?.title = ""
        statusItem.button?.image = NSImage(named: "AppIcon")
        statusItem.button?.image?.size = NSSize(width: 24, height: 24)
    }

    /// El menú muestra estado y acciones del día a día. Todo lo configurable
    /// vive en la ventana de ajustes.
    func update(
        validToken: Bool,
        text: String?,
        office: Office?,
        lastUpdate: Date?,
        name: String,
        paused: Bool,
        holidayEndDate: Date?
    ) {
        // No volver a accessory mientras la ventana de ajustes está abierta: perdería el foco.
        if !SettingsWindowController.isWindowVisible {
            NSApp.setActivationPolicy(.accessory)
        }

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
            if paused {
                // Pausar y reanudar se hace en Ajustes, pero el menú tiene que decir por
                // qué MOSSU no está actualizando; si no, parece averiado.
                lastUpdateText = "Actualizaciones en pausa"
            } else if !SchedulePreferences.shared.isDayEnabled(weekday) {
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

        // Las vacaciones se activan y cancelan en Ajustes; aquí solo se ve hasta cuándo.
        if let endDate = holidayEndDate {
            formatter.timeStyle = .none
            let endString = formatter.string(from: endDate)
            menu.addItem(
                NSMenuItem(
                    title: "🌴 Vacaciones — vuelves el \(endString)",
                    action: nil,
                    keyEquivalent: ""
                )
            )
            menu.addItem(NSMenuItem.separator())
        }

        addLAPSItem(to: menu)

        menu.addItem(NSMenuItem.separator())

        if addQuickLinksSection(to: menu) {
            menu.addItem(NSMenuItem.separator())
        }

        menu.addItem(
            NSMenuItem(
                title: "⚙️ Ajustes…",
                action: #selector(AppDelegate.showSettings),
                keyEquivalent: ","
            )
        )

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

    /// Elevación a administrador con LAPS. El título refleja el estado actual.
    private func addLAPSItem(to menu: NSMenu) {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        configureLAPSItem(item)
        menu.addItem(item)
        lapsMenuItem = item

        // El menú se construye cada pocos minutos, así que el tiempo restante se
        // recalcula justo al abrirlo para que no se vea desfasado.
        menu.delegate = menuRefresher
    }

    /// Mientras ya eres admin la fila es informativa: LAPS no deja renovar, así que
    /// no tiene acción ni muestra atajo (que además está desregistrado).
    private func configureLAPSItem(_ item: NSMenuItem) {
        let manager = LAPSManager.shared

        if manager.isRunning {
            item.title = "⏳ Activando admin…"
            item.action = nil
            applyShortcut(nil, to: item)
            return
        }

        if manager.isAdmin {
            if let remaining = manager.remainingElevation {
                let minutes = max(1, Int(ceil(remaining / 60)))
                item.title = "🔓 Admin activo · quedan \(minutes) min"
            } else {
                item.title = "🔓 Admin activo"
            }
            item.action = nil
            applyShortcut(nil, to: item)
            return
        }

        item.title = "🔒 LAPS"
        item.action = #selector(AppDelegate.runLAPS)
        applyShortcut(.lapsElevate, to: item)
    }

    /// `setShortcut` es @MainActor (consulta la distribución de teclado activa) y este
    /// método no lo es, así que se aplica en el siguiente turno del run loop.
    private func applyShortcut(_ name: KeyboardShortcuts.Name?, to item: NSMenuItem) {
        Task { @MainActor in item.setShortcut(for: name) }
    }

    /// Cada atajo es una fila del menú en modo lectura, con su combinación de teclas.
    /// La única acción es el aviso de permiso, que abre la pestaña de atajos.
    /// Devuelve `true` si ha añadido algo al menú.
    @discardableResult
    private func addQuickLinksSection(to menu: NSMenu) -> Bool {
        let visibleLinks = QuickLinkStore.shared.links.compactMap { link -> (QuickLink, String)? in
            guard let title = link.menuTitle else { return nil }
            return (link, title)
        }

        guard !visibleLinks.isEmpty else { return false }

        if !SelectionReader.hasAccessibilityPermission {
            menu.addItem(
                NSMenuItem(
                    title: "⚠️ Falta permiso de Accesibilidad",
                    action: #selector(AppDelegate.showQuickLinks),
                    keyEquivalent: ""
                )
            )
        }

        for (link, title) in visibleLinks {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            menu.addItem(item)
            applyShortcut(link.shortcutName, to: item)
        }

        return true
    }
}
