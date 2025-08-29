import Cocoa
import CoreLocation

protocol SlackStatusManagerDelegate: AnyObject {
    func slackStatusManager(_ manager: SlackStatusManager, didUpdate office: Office?)
    func slackStatusManager(_ manager: SlackStatusManager, showMessage text: String)
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

    private let locationManager = CLLocationManager()
    private let reachability = Reachability()
    private var hasPendingLocationUpdate = false

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
        // Solicitar permiso solo "When In Use" para evitar conflictos con MDM
        // y reducir fricción. La app realiza peticiones puntuales con requestLocation().
        if CLLocationManager.authorizationStatus() == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func startTracking() {
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100
        locationManager.requestLocation()
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
            let weekday = Calendar.current.component(.weekday, from: Date())
            if Office.unavailableDays.contains(weekday) {
                LogManager.shared.log("🟠 Sin actualizar Slack por el día")
                return
            }
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= Office.workingHoursEnd || hour < Office.workingHoursStart {
                LogManager.shared.log("🟠 Sin actualizar Slack por la hora")
                return
            }
        } else {
            LogManager.shared.log("🌴 Estás en vacaciones, pero actualizamos")
        }
        
        let updatedOffice = Office(location: newOffice.location,
                                   emoji: newOffice.emoji,
                                   text: statusText,
                                   ssids: newOffice.ssids,
                                   barIconImage: newOffice.barIconImage)
        
        Slack.update(given: updatedOffice, token: token) { [weak self] error in
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
}

extension SlackStatusManager: CLLocationManagerDelegate, ReachabilityDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        delegate?.slackStatusManager(self, didUpdate: currentOffice)
        // En cuanto haya autorización, intentamos obtener ubicación
        switch status {
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
