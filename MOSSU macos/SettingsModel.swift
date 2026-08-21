import Combine
import Foundation

extension Notification.Name {
    /// Se emite cuando cambia cualquier ajuste que el menú de la barra refleja.
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

/// Puente entre la ventana de ajustes (SwiftUI) y los managers de la app (AppKit).
/// Los managers no son observables, así que las escrituras avisan a mano.
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    enum Tab: Hashable {
        case general
        case schedule
        case calendar
        case shortcuts
    }

    struct CalendarOption: Identifiable, Hashable {
        let id: String
        let title: String
        let source: String
    }

    @Published var selectedTab: Tab = .general

    private weak var slackManager: SlackStatusManager?
    private var launchAtLoginManager: LaunchAtLoginManager?
    private var checkForUpdatesAction: (() -> Void)?
    private var showLogsAction: (() -> Void)?
    private var startHolidayAction: ((Date) -> Void)?

    private init() {}

    func configure(slackManager: SlackStatusManager,
                   launchAtLoginManager: LaunchAtLoginManager,
                   checkForUpdates: @escaping () -> Void,
                   showLogs: @escaping () -> Void,
                   startHoliday: @escaping (Date) -> Void) {
        self.slackManager = slackManager
        self.launchAtLoginManager = launchAtLoginManager
        self.checkForUpdatesAction = checkForUpdates
        self.showLogsAction = showLogs
        self.startHolidayAction = startHoliday
    }

    /// Refresca la ventana cuando el estado cambia desde fuera (permisos, calendarios…).
    func refresh() {
        objectWillChange.send()
    }

    private func notifyMenu() {
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    // MARK: - General

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var launchAtLoginEnabled: Bool {
        get { launchAtLoginManager?.isEnabled ?? false }
        set {
            objectWillChange.send()
            launchAtLoginManager?.setEnabled(newValue)
            LogManager.shared.log(newValue ? "Abrir al iniciar sesión: activado" : "Abrir al iniciar sesión: desactivado")
        }
    }

    func checkForUpdates() {
        checkForUpdatesAction?()
    }

    func showLogs() {
        showLogsAction?()
    }

    // MARK: - Estado de Slack

    var lastUpdate: Date? {
        slackManager?.lastUpdate
    }

    /// Rehace la detección (red y ubicación) y manda el estado saltándose el horario.
    func forceUpdate() {
        objectWillChange.send()
        LogManager.shared.log("🔄 Actualización forzada desde Ajustes")
        slackManager?.allowNextUpdateBypassingScheduleRestrictions()
        slackManager?.startTracking()
        notifyMenu()
    }

    var updatesPaused: Bool {
        get { slackManager?.paused ?? false }
        set {
            guard newValue != updatesPaused else { return }
            objectWillChange.send()
            // Al reanudar, `togglePause` limpia también vacaciones y silencio.
            slackManager?.togglePause()
            LogManager.shared.log(newValue ? "Actualización pausada" : "Reanudando actualizaciones")
            notifyMenu()
        }
    }

    var holidayEndDate: Date? {
        slackManager?.activeHolidayEndDate
    }

    func startHoliday(until date: Date) {
        objectWillChange.send()
        startHolidayAction?(date)
        notifyMenu()
    }

    func cancelHoliday() {
        objectWillChange.send()
        slackManager?.cancelHoliday()
        notifyMenu()
    }

    // MARK: - Horario

    let selectableHours = Array(6..<21)

    /// Días de la semana de lunes a domingo, con su número de `Calendar` (1 = domingo).
    var weekdays: [(number: Int, symbol: String)] {
        let symbols = DateFormatter().shortWeekdaySymbols ?? []
        return [2, 3, 4, 5, 6, 7, 1].compactMap { number in
            guard symbols.indices.contains(number - 1) else { return nil }
            return (number, symbols[number - 1].uppercasedFirst())
        }
    }

    func isDayEnabled(_ weekday: Int) -> Bool {
        SchedulePreferences.shared.isDayEnabled(weekday)
    }

    func toggleDay(_ weekday: Int) {
        objectWillChange.send()
        SchedulePreferences.shared.toggleDay(weekday)
        notifyMenu()
    }

    func isHourEnabled(_ hour: Int) -> Bool {
        SchedulePreferences.shared.isHourEnabled(hour)
    }

    func toggleHour(_ hour: Int) {
        objectWillChange.send()
        SchedulePreferences.shared.toggleHour(hour)
        notifyMenu()
    }

    func setAllHours(enabled: Bool) {
        objectWillChange.send()
        SchedulePreferences.shared.enabledHours = enabled ? Set(selectableHours) : []
        notifyMenu()
    }

    // MARK: - Calendario

    var meetingIntegrationEnabled: Bool {
        get { slackManager?.meetingIntegrationEnabled ?? false }
        set {
            objectWillChange.send()
            slackManager?.meetingIntegrationEnabled = newValue
            notifyMenu()
        }
    }

    var calendarPermissionsGranted: Bool {
        slackManager?.calendarPermissionsGranted ?? false
    }

    var availableCalendars: [CalendarOption] {
        (slackManager?.availableCalendars ?? []).map {
            CalendarOption(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title)
        }
    }

    /// Sin selección explícita, MOSSU observa todos los calendarios.
    var watchesAllCalendars: Bool {
        get { slackManager?.selectedCalendarIdentifiers.isEmpty ?? true }
        set {
            objectWillChange.send()
            if newValue {
                slackManager?.toggleCalendarSelection(identifier: nil)
            } else if let first = availableCalendars.first {
                slackManager?.toggleCalendarSelection(identifier: first.id)
            }
        }
    }

    func isCalendarSelected(_ identifier: String) -> Bool {
        slackManager?.selectedCalendarIdentifiers.contains(identifier) ?? false
    }

    func toggleCalendar(_ identifier: String) {
        objectWillChange.send()
        slackManager?.toggleCalendarSelection(identifier: identifier)
    }

    func requestCalendarAccess() {
        slackManager?.requestCalendarAccess()
    }
}
