import Cocoa
import CoreLocation
import EventKit

protocol SlackStatusManagerDelegate: AnyObject {
    func slackStatusManager(_ manager: SlackStatusManager, didUpdate office: Office?)
    func slackStatusManager(_ manager: SlackStatusManager, showMessage text: String)
    func slackStatusManagerDidUpdateCalendarPreferences(_ manager: SlackStatusManager)
}

class SlackStatusManager: NSObject {
    weak var delegate: SlackStatusManagerDelegate?
    var name: String = "El muchacho"
    var paused: Bool = false
    var lastUpdate: Date?
    var holidayEndDate: Date? {
        didSet { UserDefaults.standard.set(holidayEndDate, forKey: "holidayEndDate") }
    }
    private var holidayTimer: Timer?
    var currentOffice: Office? {
        didSet { delegate?.slackStatusManager(self, didUpdate: currentOffice) }
    }
    var token: String? {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }
    var meetingIntegrationEnabled: Bool = UserDefaults.standard.bool(forKey: "meetingIntegrationEnabled") {
        didSet {
            UserDefaults.standard.set(meetingIntegrationEnabled, forKey: "meetingIntegrationEnabled")
            if meetingIntegrationEnabled {
                LogManager.shared.log("📆 Modo reuniones ACTIVADO")
                requestCalendarAccess()
            } else {
                LogManager.shared.log("📆 Modo reuniones DESACTIVADO")
                stopCalendarMonitoring()
                // Restaurar estado por ubicación inmediatamente
                startTracking()
            }
        }
    }

    private let locationManager = CLLocationManager()
    private let reachability = Reachability()
    private var hasPendingLocationUpdate = false
    private let eventStore = EKEventStore()
    private var calendarAccessGranted = false
    private var calendarRefreshTimer: Timer?
    private var meetingEndDate: Date?
    private var meetingLastEventIdentifier: String?
    private var meetingStatusTimer: Timer?
    private var shouldBypassScheduleRestrictionsOnce = false
    private enum DefaultsKeys {
        static let selectedCalendarIdentifier = "selectedCalendarIdentifier"
    }
    private(set) var selectedCalendarIdentifier: String? = UserDefaults.standard.string(forKey: DefaultsKeys.selectedCalendarIdentifier)
    var calendarPermissionsGranted: Bool { calendarAccessGranted }

    private func isWithinWorkingHours(at date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        guard SchedulePreferences.shared.isDayEnabled(weekday) else { return false }
        let hour = calendar.component(.hour, from: date)
        return SchedulePreferences.shared.isHourEnabled(hour)
    }

    override init() {
        super.init()
        locationManager.delegate = self
        reachability.delegate = self
        reachability.startInternetTracking()
        holidayEndDate = UserDefaults.standard.value(forKey: "holidayEndDate") as? Date
        
        // Observar cuando se activa la pantalla
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func requestAuthorization() {
        // Para builds en la barra de menú necesitamos acceso continuo; intentamos
        // solicitar "Always" (cuando está disponible) y retrocedemos a "When In Use".
        switch locationManager.authorizationStatus {
        case .notDetermined:
            requestAlwaysAuthorizationIfAvailable()
        case .authorizedWhenInUse:
            LogManager.shared.log("ℹ️ Permiso actual: 'Cuando se use la app'. Intentando elevar a 'Siempre'.")
            requestAlwaysAuthorizationIfAvailable()
        case .denied, .restricted:
            LogManager.shared.log("🛑 Permiso de localización denegado/restringido. Actualiza los ajustes para permitir acceso siempre.")
        default:
            break
        }
    }

    private func requestAlwaysAuthorizationIfAvailable() {
        if locationManager.responds(to: #selector(CLLocationManager.requestAlwaysAuthorization)) {
            locationManager.requestAlwaysAuthorization()
            LogManager.shared.log("📍 Solicitando permiso de localización 'Siempre'")
        } else {
            locationManager.requestWhenInUseAuthorization()
            LogManager.shared.log("📍 Solicitando permiso de localización 'Cuando se use la app'")
        }
    }

    func requestCalendarAccess() {
        eventStore.requestAccess(to: .event) { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.calendarAccessGranted = granted
                if granted {
                    LogManager.shared.log("📆 Calendario: acceso concedido")
                    self.validateSelectedCalendar()
                    self.startCalendarMonitoring()
                } else {
                    LogManager.shared.log("🛑 Calendario: acceso denegado")
                    self.clearSelectedCalendar(persist: true)
                    self.meetingIntegrationEnabled = false
                }
                self.delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
            }
        }
    }

    func startTracking() {
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100
        locationManager.requestLocation()
    }

    func allowNextUpdateBypassingScheduleRestrictions() {
        shouldBypassScheduleRestrictionsOnce = true
    }

    func updateSelectedCalendar(identifier: String?) {
        let normalizedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedIdentifier == selectedCalendarIdentifier {
            return
        }
        guard calendarAccessGranted else {
            clearSelectedCalendar(persist: true)
            delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
            return
        }
        if let normalizedIdentifier = normalizedIdentifier, !normalizedIdentifier.isEmpty {
            guard let calendar = eventStore.calendar(withIdentifier: normalizedIdentifier) else {
                LogManager.shared.log("⚠️ Calendario seleccionado no encontrado. Se usará la lista completa.")
                if clearSelectedCalendar(persist: true) {
                    delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
                }
                return
            }
            selectedCalendarIdentifier = calendar.calendarIdentifier
            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: DefaultsKeys.selectedCalendarIdentifier)
            LogManager.shared.log("📆 Calendario observado: \(calendar.title) – \(calendar.source.title)")
        } else {
            if clearSelectedCalendar(persist: true) {
                LogManager.shared.log("📆 Observando todos los calendarios disponibles")
                delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
            }
            return
        }
        if meetingIntegrationEnabled {
            startCalendarMonitoring()
        }
        delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
    }

    var availableCalendars: [EKCalendar] {
        guard calendarAccessGranted else { return [] }
        return eventStore
            .calendars(for: .event)
            .sorted { lhs, rhs in
                if lhs.source.title == rhs.source.title {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.source.title.localizedCaseInsensitiveCompare(rhs.source.title) == .orderedAscending
            }
    }

    private func validateSelectedCalendar() {
        guard calendarAccessGranted else { return }
        guard let identifier = selectedCalendarIdentifier else { return }
        guard eventStore.calendar(withIdentifier: identifier) != nil else {
            if clearSelectedCalendar(persist: true) {
                LogManager.shared.log("⚠️ Calendario seleccionado ya no disponible. Se usará la lista completa.")
                delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
            }
            return
        }
    }

    @discardableResult
    private func clearSelectedCalendar(persist: Bool) -> Bool {
        guard selectedCalendarIdentifier != nil else { return false }
        selectedCalendarIdentifier = nil
        if persist {
            UserDefaults.standard.removeObject(forKey: DefaultsKeys.selectedCalendarIdentifier)
        }
        return true
    }

    private func calendarsForQuery() -> [EKCalendar]? {
        guard calendarAccessGranted else { return nil }
        guard let identifier = selectedCalendarIdentifier else { return nil }
        guard let calendar = eventStore.calendar(withIdentifier: identifier) else {
            if clearSelectedCalendar(persist: true) {
                LogManager.shared.log("⚠️ Calendario seleccionado ya no disponible. Se usará la lista completa.")
                delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
            }
            return nil
        }
        return [calendar]
    }

    func startCalendarMonitoring() {
        calendarRefreshTimer?.invalidate()
        guard calendarAccessGranted, meetingIntegrationEnabled else { return }
        NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: eventStore)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.calendarStoreChanged),
                                               name: .EKEventStoreChanged,
                                               object: eventStore)
        validateSelectedCalendar()
        checkCalendarAndUpdateIfNeeded()
    }

    func stopCalendarMonitoring() {
        calendarRefreshTimer?.invalidate()
        meetingStatusTimer?.invalidate()
        meetingEndDate = nil
        meetingLastEventIdentifier = nil
        NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: eventStore)
    }

    func getCurrentStatus(token: String) {
        Slack.getStatus(token: token) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let (status, name)):
                self.name = name
                let office = Office.given(emoji: status)
                LogManager.shared.log("Tu estado de Slack es \"\(office?.text ?? "")\"")
                self.currentOffice = office
            case .failure(let error):
                if !error.isConnectionProblem() {
                    self.token = nil
                    UserDefaults.standard.removeObject(forKey: "token")
                }
            }
            self.startTracking()
            if self.meetingIntegrationEnabled && self.calendarAccessGranted { self.startCalendarMonitoring() }
        }
    }

    func sendHoliday(until endDate: Date) {
        paused = true
        holidayEndDate = endDate
        scheduleHolidayTimer()
        sendToSlack(office: holiday)
    }
    
    private func scheduleHolidayTimer() {
        holidayTimer?.invalidate()
        guard let endDate = holidayEndDate else { return }
        let interval = endDate.timeIntervalSinceNow
        if interval > 0 {
            holidayTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.paused = false
                self.holidayEndDate = nil
                UserDefaults.standard.removeObject(forKey: "holidayEndDate")
                self.startTracking()
            }
        } else {
            paused = false
            holidayEndDate = nil
            UserDefaults.standard.removeObject(forKey: "holidayEndDate")
            startTracking()
        }
    }

    func togglePause() {
        paused.toggle()
        if !paused {
            holidayEndDate = nil
            UserDefaults.standard.removeObject(forKey: "holidayEndDate")
            UserDefaults.standard.removeObject(forKey: "mutedUntil")
            holidayTimer?.invalidate()
            startTracking()
        }
    }

    private func sendToSlack(office: Office) {
        var newOffice = office
        
        guard let token = token else { return }
        let bypassScheduleRestrictions = shouldBypassScheduleRestrictionsOnce
        if bypassScheduleRestrictions {
            shouldBypassScheduleRestrictionsOnce = false
        }
        
        var statusText = office.text
        if let endDate = holidayEndDate, Date() < endDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.locale = Locale.current
            newOffice = holiday
            statusText = "🌴 hasta el \(formatter.string(from: endDate))"
        } else if currentOffice != nil {
            delegate?.slackStatusManager(self, didUpdate: currentOffice)
        }
        
        if newOffice != holiday {
            if paused {
                LogManager.shared.log("⏸️ Sin actualizar Slack por estar en pausa")
                return
            }
            if !bypassScheduleRestrictions {
                let weekday = Calendar.current.component(.weekday, from: Date())
                let isDayEnabled = SchedulePreferences.shared.isDayEnabled(weekday)
                let hour = Calendar.current.component(.hour, from: Date())
                let isHourEnabled = SchedulePreferences.shared.isHourEnabled(hour)
                if (!isDayEnabled || !isHourEnabled) && newOffice == remote {
                    LogManager.shared.log("🟠 Sin actualizar Slack: remoto fuera de horario laboral")
                    return
                }
            }
        } else {
            LogManager.shared.log("🌴 Estás en vacaciones, pero actualizamos")
        }

        let updatedOffice = Office(location: newOffice.location,
                                   emoji: newOffice.emoji,
                                   text: statusText,
                                   ssids: newOffice.ssids,
                                   barIconImage: newOffice.barIconImage,
                                   emojiMeeting: newOffice.emojiMeeting,
                                   barIconImageMeeting: newOffice.barIconImageMeeting
        )
        
        Slack.update(given: updatedOffice, token: token, expiration: 0) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                if !error.isConnectionProblem() {
                    self.token = nil
                    UserDefaults.standard.removeObject(forKey: "token")
                }
                return
            }

            LogManager.shared.log("✅ Slack actualizado correctamente a \"\(updatedOffice.text)\"")
            self.lastUpdate = Date()
            if self.currentOffice != updatedOffice {
                self.delegate?.slackStatusManager(self, showMessage: updatedOffice.text)
            }
            self.currentOffice = updatedOffice
        }
    }

    // MARK: - Calendar / Meetings

    @objc private func calendarStoreChanged() {
        LogManager.shared.log("📆 Cambios en calendario - reevaluando")
        delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
        checkCalendarAndUpdateIfNeeded()
    }

    private func checkCalendarAndUpdateIfNeeded() {
        guard calendarAccessGranted, meetingIntegrationEnabled else {
            calendarRefreshTimer?.invalidate()
            return
        }
        guard !paused else {
            calendarRefreshTimer?.invalidate()
            return
        }
        let now = Date()
        let start = now.addingTimeInterval(-300)
        let end = now.addingTimeInterval(7200)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendarsForQuery())
        let events = eventStore.events(matching: predicate).filter { !$0.isAllDay }
        let ongoingEvents = events
            .filter { $0.startDate <= now && $0.endDate > now }
            .sorted(by: { $0.endDate < $1.endDate })
        let upcomingEvents = events
            .filter { $0.startDate > now && $0.availability != .free }
            .sorted(by: { $0.startDate < $1.startDate })
        let withinWorkingHours = isWithinWorkingHours(at: now)

        if let nextStart = upcomingEvents.first?.startDate {
            scheduleCalendarRefresh(at: nextStart)
        } else {
            calendarRefreshTimer?.invalidate()
        }

        if let current = ongoingEvents.first {
            // Considerar relevantes todos salvo marcados como "free"
            let isRelevant = current.availability != .free
            if isRelevant {
                guard withinWorkingHours else {
                    LogManager.shared.log("🕘 Reunión fuera de horario laboral - no se actualiza estado")
                    return
                }
                if meetingLastEventIdentifier != current.eventIdentifier || meetingEndDate != current.endDate {
                    meetingLastEventIdentifier = current.eventIdentifier
                    meetingEndDate = current.endDate
                    scheduleMeetingEndTimer()
                    LogManager.shared.log("🗓️ Reunión detectada hasta \(current.endDate ?? Date())")
                    sendMeetingEmojiUpdate()
                }
                return
            }
        }

        guard withinWorkingHours else {
            LogManager.shared.log("🕘 Fuera de horario laboral - no se altera el estado")
            return
        }

        // No hay reunión activa
        if meetingEndDate != nil || meetingLastEventIdentifier != nil {
            LogManager.shared.log("✅ Fin de reunión - restaurar emoji de ubicación")
        }
        meetingEndDate = nil
        meetingLastEventIdentifier = nil
        meetingStatusTimer?.invalidate()
        // Forzar una actualización por ubicación
        startTracking()
    }

    private func scheduleCalendarRefresh(at date: Date) {
        calendarRefreshTimer?.invalidate()
        let interval = date.timeIntervalSinceNow
        if interval <= 0 {
            DispatchQueue.main.async { [weak self] in
                self?.checkCalendarAndUpdateIfNeeded()
            }
            return
        }
        calendarRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval + 1, repeats: false) { [weak self] _ in
            self?.checkCalendarAndUpdateIfNeeded()
        }
        LogManager.shared.log("⏰ Próxima revisión de calendario programada a las \(date)")
    }

    private func sendMeetingEmojiUpdate() {
        guard let token = token else { return }
        guard let endDate = meetingEndDate, endDate > Date() else { return }
        // Mantener texto de la ubicación actual; si aún no hay, usar remoto
        let office = currentOffice ?? remote
        let officeForSlack = Office(location: office.location,
                                    emoji: office.emojiMeeting,
                                    text: office.text,
                                    ssids: office.ssids,
                                    barIconImage: office.barIconImageMeeting,
                                    emojiMeeting: office.emojiMeeting,
                                    barIconImageMeeting: office.barIconImageMeeting)
        let expiration = Int(endDate.timeIntervalSince1970)
        LogManager.shared.log("📣 Actualizando emoji de Slack por reunión (expira: \(endDate))")
        currentOffice = officeForSlack
        Slack.update(given: officeForSlack, token: token, expiration: expiration) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                if !error.isConnectionProblem() {
                    self.token = nil
                    UserDefaults.standard.removeObject(forKey: "token")
                }
                return
            }
            self.lastUpdate = Date()
            LogManager.shared.log("✅ Emoji de reunión aplicado correctamente")
        }
    }

    private func scheduleMeetingEndTimer() {
        meetingStatusTimer?.invalidate()
        guard let endDate = meetingEndDate else { return }
        let interval = endDate.timeIntervalSinceNow
        if interval > 0 {
            meetingStatusTimer = Timer.scheduledTimer(withTimeInterval: interval + 2, repeats: false) { [weak self] _ in
                self?.checkCalendarAndUpdateIfNeeded()
            }
        }
    }
}

extension SlackStatusManager: CLLocationManagerDelegate, ReachabilityDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        delegate?.slackStatusManager(self, didUpdate: currentOffice)
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startTracking()
        case .denied, .restricted:
            LogManager.shared.log("🛑 Permiso de localización denegado o restringido")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard NSScreen.hasActiveDisplay() else {
            LogManager.shared.log("🛑 No hay pantalla disponible")
            return
        }
        guard !paused else {
            LogManager.shared.log("🛑 Estás en modo pausa")
            return
        }
        if meetingIntegrationEnabled, let end = meetingEndDate, end > Date() {
            LogManager.shared.log("🛑 En reunión - no actualizamos por ubicación")
            return
        }
        let currentSSID = Office.SSID.current()
        LogManager.shared.log("SSID: \(currentSSID.rawValue)")
        let office = Office.given(ssid: currentSSID, currentLocation: locations.last)
        LogManager.shared.log("Ubicación identificada como \"\(office.text)\"")
        sendToSlack(office: office)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        LogManager.shared.log("🛑 Error al trazar ubicación: \(error)")
        if let clErr = error as? CLError, clErr.code == .denied {
            LogManager.shared.log("ℹ️ Revisa Ajustes del Sistema → Privacidad y seguridad → Localización y habilita MOSSU.")
        }
    }
    
    func reachability(_ reachability: Reachability, didUpdateInternetStatus isAvailable: Bool) {
        if isAvailable {
            LogManager.shared.log("🛜 Internet disponible - obteniendo ubicación")
            
            // Si no hay pantalla activa, marcar como pendiente para cuando se abra
            if !NSScreen.hasActiveDisplay() {
                LogManager.shared.log("📱 Pantalla cerrada - marcando actualización como pendiente")
                hasPendingLocationUpdate = true
            } else {
                startTracking()
            }
        } else {
            LogManager.shared.log("❌ Internet no disponible")
        }
    }
    
    @objc private func screenDidWake() {
        LogManager.shared.log("🌅 Pantalla activada")
        
        // Si hay una actualización pendiente, ejecutarla ahora
        if hasPendingLocationUpdate {
            LogManager.shared.log("🔄 Ejecutando actualización pendiente tras abrir pantalla")
            hasPendingLocationUpdate = false
            startTracking()
        }
    }
}
