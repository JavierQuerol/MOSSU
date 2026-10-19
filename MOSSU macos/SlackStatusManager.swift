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
    var paused: Bool = UserDefaults.standard.bool(forKey: "paused") {
        didSet { UserDefaults.standard.set(paused, forKey: "paused") }
    }
    var lastUpdate: Date?
    var holidayEndDate: Date? {
        didSet { UserDefaults.standard.set(holidayEndDate, forKey: "holidayEndDate") }
    }
    /// Las vacaciones solo cuentan si la fecha de vuelta todavía no ha llegado.
    var isOnHoliday: Bool {
        guard let endDate = holidayEndDate else { return false }
        return Date() < endDate
    }
    /// Fecha de vuelta para la UI: nil en cuanto las vacaciones han terminado.
    var activeHolidayEndDate: Date? { isOnHoliday ? holidayEndDate : nil }
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
    /// Al llegar a un sitio la primera petición de ubicación puede fallar (la Wi-Fi recién
    /// conectada aún no sirve para ubicarse) y, sin reintento, el estado se quedaría como
    /// estaba hasta el siguiente cambio de red.
    private static let maxLocationRetries = 3
    private static let locationRetryDelay: TimeInterval = 30
    private var locationRetriesLeft = 0
    private var locationRetryTimer: Timer?
    private var lastWakeHandledAt: Date?
    private let eventStore = EKEventStore()
    private var calendarAccessGranted = false
    private var calendarRefreshTimer: Timer?
    private var meetingEndDate: Date?
    private var meetingLastEventIdentifier: String?
    private var meetingStatusTimer: Timer?
    private var shouldBypassScheduleRestrictionsOnce = false
    private var shouldAllowScreenClosedUpdateOnce = false
    private enum DefaultsKeys {
        static let selectedCalendarIdentifiers = "selectedCalendarIdentifiers"
        static let legacySelectedCalendarIdentifier = "selectedCalendarIdentifier"
    }
    private(set) var selectedCalendarIdentifiers: Set<String>
    var calendarPermissionsGranted: Bool { calendarAccessGranted }

    private static func loadStoredCalendarIdentifiers() -> Set<String> {
        let defaults = UserDefaults.standard

        if let stored = defaults.array(forKey: DefaultsKeys.selectedCalendarIdentifiers) as? [String] {
            return Set(stored)
        }

        if let legacy = defaults.string(forKey: DefaultsKeys.legacySelectedCalendarIdentifier), !legacy.isEmpty {
            defaults.removeObject(forKey: DefaultsKeys.legacySelectedCalendarIdentifier)
            defaults.set([legacy], forKey: DefaultsKeys.selectedCalendarIdentifiers)
            return Set([legacy])
        }

        return []
    }

    private func isWithinWorkingHours(at date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        guard SchedulePreferences.shared.isDayEnabled(weekday) else { return false }
        let hour = calendar.component(.hour, from: date)
        return SchedulePreferences.shared.isHourEnabled(hour)
    }

    override init() {
        selectedCalendarIdentifiers = Self.loadStoredCalendarIdentifiers()
        super.init()
        locationManager.delegate = self
        reachability.delegate = self
        reachability.startInternetTracking()
        holidayEndDate = UserDefaults.standard.value(forKey: "holidayEndDate") as? Date
        // Las vacaciones pueden haber terminado con la app cerrada: el timer no sobrevive
        // al reinicio, así que hay que revisar la fecha guardada y reponerlo si toca.
        if !expireHolidayIfNeeded() {
            // Unas vacaciones vigentes implican pausa, aunque vengan de una versión que
            // no la guardaba: si no, el menú y el toggle de Ajustes dirían lo contrario.
            if isOnHoliday { paused = true }
            scheduleHolidayTimer()
        }
        
        // Observar cuando se activa la pantalla. Hacen falta las dos: `didWake` es el
        // despertar del sistema y `screensDidWake` el de las pantallas, que es lo que
        // ocurre al abrir la tapa si el Mac seguía despierto.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
                    self.validateSelectedCalendars()
                    self.startCalendarMonitoring()
                } else {
                    LogManager.shared.log("🛑 Calendario: acceso denegado")
                    self.setSelectedCalendars([], persist: true)
                    self.meetingIntegrationEnabled = false
                }
                self.delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
            }
        }
    }

    func startTracking() {
        // Cada petición nueva (los reintentos no) vuelve a tener todos los reintentos.
        locationRetriesLeft = Self.maxLocationRetries
        requestLocation()
    }

    private func requestLocation() {
        locationRetryTimer?.invalidate()
        expireHolidayIfNeeded()
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100
        locationManager.requestLocation()
    }

    private func scheduleLocationRetry() {
        guard locationRetriesLeft > 0 else {
            LogManager.shared.log("🛑 Sin ubicación tras varios intentos - se esperará al siguiente cambio de red")
            return
        }
        locationRetriesLeft -= 1
        LogManager.shared.log("🔁 Se reintentará la ubicación en \(Int(Self.locationRetryDelay)) s")
        locationRetryTimer?.invalidate()
        locationRetryTimer = Timer.scheduledTimer(withTimeInterval: Self.locationRetryDelay, repeats: false) { [weak self] _ in
            self?.requestLocation()
        }
    }

    func allowNextUpdateBypassingScheduleRestrictions() {
        shouldBypassScheduleRestrictionsOnce = true
    }

    func toggleCalendarSelection(identifier: String?) {
        guard calendarAccessGranted else {
            setSelectedCalendars([], persist: true)
            return
        }

        guard let identifier = identifier, !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if !selectedCalendarIdentifiers.isEmpty {
                LogManager.shared.log("📆 Observando todos los calendarios disponibles")
                setSelectedCalendars([], persist: true)
            }
            return
        }

        guard let calendar = eventStore.calendar(withIdentifier: identifier) else {
            LogManager.shared.log("⚠️ Calendario seleccionado no encontrado. Se usará la lista completa.")
            setSelectedCalendars([], persist: true)
            return
        }

        var updated = selectedCalendarIdentifiers
        if updated.contains(calendar.calendarIdentifier) {
            updated.remove(calendar.calendarIdentifier)
            LogManager.shared.log("📆 Deja de observar: \(calendar.title) – \(calendar.source.title)")
            if updated.isEmpty {
                LogManager.shared.log("📆 Observando todos los calendarios disponibles")
            }
        } else {
            updated.insert(calendar.calendarIdentifier)
            LogManager.shared.log("📆 Observando calendario: \(calendar.title) – \(calendar.source.title)")
        }

        setSelectedCalendars(updated, persist: true)
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

    private func validateSelectedCalendars() {
        guard calendarAccessGranted else { return }
        guard !selectedCalendarIdentifiers.isEmpty else { return }

        var missingIdentifiers: Set<String> = []
        for identifier in selectedCalendarIdentifiers {
            if eventStore.calendar(withIdentifier: identifier) == nil {
                missingIdentifiers.insert(identifier)
            }
        }

        if !missingIdentifiers.isEmpty {
            selectedCalendarIdentifiers.subtract(missingIdentifiers)
            persistSelectedCalendars()
            LogManager.shared.log("⚠️ Algunos calendarios seleccionados ya no están disponibles. Se observarán los restantes.")
            delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
        }
    }

    private func persistSelectedCalendars() {
        let defaults = UserDefaults.standard
        if selectedCalendarIdentifiers.isEmpty {
            defaults.removeObject(forKey: DefaultsKeys.selectedCalendarIdentifiers)
        } else {
            let sortedIdentifiers = Array(selectedCalendarIdentifiers).sorted()
            defaults.set(sortedIdentifiers, forKey: DefaultsKeys.selectedCalendarIdentifiers)
        }
        defaults.removeObject(forKey: DefaultsKeys.legacySelectedCalendarIdentifier)
    }

    @discardableResult
    private func setSelectedCalendars(_ identifiers: Set<String>, persist: Bool) -> Bool {
        guard identifiers != selectedCalendarIdentifiers else { return false }
        selectedCalendarIdentifiers = identifiers
        if persist {
            persistSelectedCalendars()
        }
        if meetingIntegrationEnabled {
            startCalendarMonitoring()
        }
        delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
        return true
    }

    private func calendarsForQuery() -> [EKCalendar]? {
        guard calendarAccessGranted else { return nil }
        guard !selectedCalendarIdentifiers.isEmpty else { return nil }

        var resolvedCalendars: [EKCalendar] = []
        var missingIdentifiers: Set<String> = []

        for identifier in selectedCalendarIdentifiers {
            if let calendar = eventStore.calendar(withIdentifier: identifier) {
                resolvedCalendars.append(calendar)
            } else {
                missingIdentifiers.insert(identifier)
            }
        }

        if !missingIdentifiers.isEmpty {
            selectedCalendarIdentifiers.subtract(missingIdentifiers)
            persistSelectedCalendars()
            LogManager.shared.log("⚠️ Calendarios no encontrados. Se usarán los disponibles.")
            delegate?.slackStatusManagerDidUpdateCalendarPreferences(self)
        }

        return resolvedCalendars.isEmpty ? nil : resolvedCalendars
    }

    func startCalendarMonitoring() {
        calendarRefreshTimer?.invalidate()
        guard calendarAccessGranted, meetingIntegrationEnabled else { return }
        NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: eventStore)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.calendarStoreChanged),
                                               name: .EKEventStoreChanged,
                                               object: eventStore)
        validateSelectedCalendars()
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
        // "Vuelvo el X" quiere decir que las vacaciones caducan a las 00:00 de ese día.
        let returnDate = Calendar.current.startOfDay(for: endDate)
        guard Date() < returnDate else {
            LogManager.shared.log("🌴 Fecha de vuelta ya pasada: no se activan vacaciones")
            return
        }
        paused = true
        holidayEndDate = returnDate
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
                self.clearHoliday()
                self.startTracking()
            }
        } else {
            clearHoliday()
            startTracking()
        }
    }

    /// Cancela las vacaciones a mano. No pasa por `togglePause` a propósito: la pausa puede
    /// no estar guardada (versiones anteriores) y entonces reanudar acabaría pausando.
    func cancelHoliday() {
        guard holidayEndDate != nil else { return }
        LogManager.shared.log("🌴 Vacaciones canceladas")
        clearHoliday()
        startTracking()
    }

    /// Borra unas vacaciones ya cumplidas. No relanza el tracking: eso lo decide quien llama.
    @discardableResult
    func expireHolidayIfNeeded() -> Bool {
        guard let endDate = holidayEndDate, Date() >= endDate else { return false }
        LogManager.shared.log("🌴 Las vacaciones han terminado")
        clearHoliday()
        return true
    }

    private func clearHoliday() {
        holidayTimer?.invalidate()
        holidayTimer = nil
        paused = false
        holidayEndDate = nil
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    func togglePause() {
        paused.toggle()
        if !paused {
            clearHoliday()
            UserDefaults.standard.removeObject(forKey: "mutedUntil")
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
        expireHolidayIfNeeded()
        if isOnHoliday {
            // El estado de vacaciones se escribe igual que cualquier otro: la fecha de
            // vuelta se ve en el menú y en Ajustes, no colgando del texto del estado.
            newOffice = holiday
            statusText = holiday.text
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
        // Lo marcado como "disponible" no es una reunión, tampoco mientras está en curso: si
        // no, un evento así que acabe antes taparía a la reunión real que se solapa con él.
        let events = eventStore.events(matching: predicate).filter { !$0.isAllDay && $0.availability != .free }
        let ongoingEvents = events
            .filter { $0.startDate <= now && $0.endDate > now }
            .sorted(by: { $0.endDate < $1.endDate })
        let upcomingEvents = events
            .filter { $0.startDate > now }
            .sorted(by: { $0.startDate < $1.startDate })
        let withinWorkingHours = isWithinWorkingHours(at: now)

        if let nextStart = upcomingEvents.first?.startDate {
            scheduleCalendarRefresh(at: nextStart)
        } else {
            calendarRefreshTimer?.invalidate()
        }

        // Fuera de horario no se empieza a mostrar ninguna reunión, pero la que ya se muestra
        // sigue hasta que acabe.
        var meeting = ongoingEvents.first
        if !withinWorkingHours {
            meeting = meetingLastEventIdentifier.flatMap { shown in
                ongoingEvents.first { $0.eventIdentifier == shown }
            }
        }

        if let current = meeting {
            if meetingLastEventIdentifier != current.eventIdentifier || meetingEndDate != current.endDate {
                meetingLastEventIdentifier = current.eventIdentifier
                meetingEndDate = current.endDate
                scheduleMeetingEndTimer()
                LogManager.shared.log("🗓️ Reunión detectada hasta \(current.endDate ?? Date())")
                // Se publica ya con el último sitio conocido; si aún no hay, remoto.
                sendMeetingEmojiUpdate(for: currentOffice ?? remote)
            }
            // Igual que sin reunión, cada revisión vuelve a pedir la ubicación: el sitio
            // conocido puede estar desfasado (portátil abierto en otro lugar, app recién
            // arrancada…) y la reunión solo debe cambiar el emoji, no congelar el sitio.
            startTracking()
            return
        }

        // No hay reunión que mostrar
        let meetingEnded = meetingEndDate != nil || meetingLastEventIdentifier != nil
        meetingEndDate = nil
        meetingLastEventIdentifier = nil
        meetingStatusTimer?.invalidate()

        guard withinWorkingHours else {
            if meetingEnded, let shownOffice = currentOffice {
                // Fuera de horario no se pide la ubicación (que además no podría poner
                // "remoto"), pero el emoji de reunión lo ha puesto MOSSU y tiene que
                // quitarlo: se deja el sitio que mostraba la reunión.
                LogManager.shared.log("✅ Fin de reunión fuera de horario - quitar emoji de reunión")
                allowNextUpdateBypassingScheduleRestrictions()
                sendToSlack(office: shownOffice.withoutMeeting)
            } else {
                LogManager.shared.log(ongoingEvents.isEmpty
                    ? "🕘 Fuera de horario laboral - no se altera el estado"
                    : "🕘 Reunión fuera de horario laboral - no se actualiza estado")
            }
            return
        }

        if meetingEnded {
            LogManager.shared.log("✅ Fin de reunión - restaurar emoji de ubicación")
            shouldAllowScreenClosedUpdateOnce = true
            if !NSScreen.hasActiveDisplay() {
                // Con el portátil cerrado la ubicación puede no llegar nunca, así que
                // se deja pendiente para reintentarlo en cuanto vuelva a estar activo.
                LogManager.shared.log("📱 Fin de reunión con el portátil cerrado - se reintentará al despertar")
                hasPendingLocationUpdate = true
            }
        }
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

    /// Publica `office` con el emoji y el icono de reunión, manteniendo su texto.
    private func sendMeetingEmojiUpdate(for office: Office) {
        guard let token = token else { return }
        guard let endDate = meetingEndDate, endDate > Date() else { return }
        let officeForSlack = office.inMeeting
        LogManager.shared.log("📣 Actualizando emoji de Slack por reunión (expira: \(endDate))")
        currentOffice = officeForSlack
        Slack.update(given: officeForSlack, token: token) { [weak self] error in
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
        locationRetryTimer?.invalidate()
        let screenIsActive = NSScreen.hasActiveDisplay()
        let canBypassScreenCheck = shouldAllowScreenClosedUpdateOnce
        if !screenIsActive && !canBypassScreenCheck {
            LogManager.shared.log("🛑 No hay pantalla disponible")
            return
        }
        if canBypassScreenCheck {
            shouldAllowScreenClosedUpdateOnce = false
            if !screenIsActive {
                LogManager.shared.log("✅ Restableciendo estado tras reunión aunque la pantalla esté cerrada")
            }
        }
        // Ha llegado la ubicación que se esperaba: ya no hay nada pendiente.
        hasPendingLocationUpdate = false
        guard !paused else {
            LogManager.shared.log("🛑 Estás en modo pausa")
            return
        }
        let currentSSID = Office.SSID.current()
        LogManager.shared.log("SSID: \(currentSSID.rawValue)")
        let office = Office.given(ssid: currentSSID, currentLocation: locations.last)
        LogManager.shared.log("Ubicación identificada como \"\(office.text)\"")
        if meetingIntegrationEnabled, let end = meetingEndDate, end > Date() {
            // En reunión la ubicación sigue decidiendo el sitio; la reunión solo pone el
            // emoji. Consume el salto de horario igual que haría `sendToSlack`.
            shouldBypassScheduleRestrictionsOnce = false
            sendMeetingEmojiUpdate(for: office)
            return
        }
        sendToSlack(office: office)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        LogManager.shared.log("🛑 Error al trazar ubicación: \(error)")
        let isDenied = (error as? CLError)?.code == .denied
        if !NSScreen.hasActiveDisplay() {
            // Cerrado no siempre hay ubicación: reintentar cuando el Mac vuelva.
            LogManager.shared.log("📱 Sin ubicación con el portátil cerrado - se reintentará al despertar")
            hasPendingLocationUpdate = true
        } else if !isDenied {
            scheduleLocationRetry()
        }
        if isDenied {
            LogManager.shared.log("ℹ️ Revisa Ajustes del Sistema → Privacidad y seguridad → Localización y habilita MOSSU.")
        }
    }
    
    func reachability(_ reachability: Reachability, didUpdateInternetStatus isAvailable: Bool) {
        if isAvailable {
            LogManager.shared.log("🛜 Internet disponible - obteniendo ubicación")
            trackWhenScreenIsActive()
        } else {
            LogManager.shared.log("❌ Internet no disponible")
        }
    }
    
    func reachability(_ reachability: Reachability, didJoinNetwork ssid: String) {
        LogManager.shared.log("🛜 Conectado a la red \(ssid) - obteniendo ubicación")
        trackWhenScreenIsActive()
    }

    private func trackWhenScreenIsActive() {
        // Si no hay pantalla activa, marcar como pendiente para cuando se abra
        if !NSScreen.hasActiveDisplay() {
            LogManager.shared.log("📱 Pantalla cerrada - marcando actualización como pendiente")
            hasPendingLocationUpdate = true
        } else {
            startTracking()
        }
    }

    @objc private func screenDidWake() {
        // Al despertar el sistema llegan las dos notificaciones casi a la vez. La segunda se
        // ignora salvo que entre medias haya quedado algo pendiente: la red suele volver justo
        // entonces, con la pantalla aún apagada, y si no se perdería hasta el siguiente despertar.
        if let last = lastWakeHandledAt, Date().timeIntervalSince(last) < 5, !hasPendingLocationUpdate { return }
        lastWakeHandledAt = Date()

        LogManager.shared.log("🌅 Pantalla activada")

        // El timer de vacaciones no dispara mientras el Mac duerme: al despertar hay que
        // cerrarlas si ya han pasado, o reponer el timer si siguen vigentes.
        let holidayJustEnded = expireHolidayIfNeeded()
        if isOnHoliday {
            scheduleHolidayTimer()
        }

        let hadPendingUpdate = hasPendingLocationUpdate
        hasPendingLocationUpdate = false

        // Si una reunión terminó con el portátil cerrado, el estado puede haberse quedado
        // en "en reunión": revisar el calendario restaura la ubicación si ya no hay ninguna
        // y, si la reunión sigue, vuelve a pedir el sitio por si lo has abierto en otro lugar.
        if meetingIntegrationEnabled {
            LogManager.shared.log("🔄 Revisando calendario y estado tras despertar")
            checkCalendarAndUpdateIfNeeded()
            return
        }

        if hadPendingUpdate || holidayJustEnded {
            LogManager.shared.log("🔄 Ejecutando actualización pendiente tras abrir pantalla")
            startTracking()
        }
    }
}
