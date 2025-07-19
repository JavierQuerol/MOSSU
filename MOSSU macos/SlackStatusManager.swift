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
    var holidayEndDate: Date?
    private var holidayTimer: Timer?
    var currentOffice: Office? {
        didSet { delegate?.slackStatusManager(self, didUpdate: currentOffice) }
    }
    var token: String? {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }

    private let locationManager = CLLocationManager()
    private let reachability = Reachability()

    override init() {
        super.init()
        locationManager.delegate = self
        reachability.delegate = self
        reachability.startInternetTracking()
    }

    func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    func startTracking() {
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 50
        locationManager.startUpdatingLocation()
    }

    func getCurrentStatus(token: String) {
        Slack.getStatus(token: token) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let (status, name)):
                self.name = name
                let office = Office.given(emoji: status)
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

    func sendHoliday() {
        paused = true
        holidayEndDate = nil
        holidayTimer?.invalidate()
        sendToSlack(office: holiday)
    }
    
    func sendHoliday(until endDate: Date) {
        paused = true
        scheduleHolidayTimer()
        sendToSlack(office: holiday)
        holidayEndDate = endDate
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
                self.startTracking()
            }
        } else {
            paused = false
            holidayEndDate = nil
            startTracking()
        }
    }

    func togglePause() {
        paused.toggle()
        if !paused {
            holidayEndDate = nil
            UserDefaults.standard.removeObject(forKey: "mutedUntil")
            startTracking()
        }
    }

    private func sendToSlack(office: Office) {
        locationManager.stopUpdatingLocation()
        
        if Date() <= holidayEndDate ?? Date(timeIntervalSinceNow: -10000000) {
            print("Not checking status, holiday not over yet")
            return
        }
        if currentOffice != nil {
            delegate?.slackStatusManager(self, didUpdate: self.currentOffice)
            return
        }
        
        guard let token = token else { return }
        Slack.update(given: office, token: token) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                if !error.isConnectionProblem() {
                    self.token = nil
                    UserDefaults.standard.removeObject(forKey: "token")
                }
                return
            }

            print("Slack actualizado correctamente a \"\(office.text)\"")
            self.lastUpdate = Date()
            if self.currentOffice != office {
                self.delegate?.slackStatusManager(self, showMessage: office.text)
            }
            self.currentOffice = office
        }
    }
}

extension SlackStatusManager: CLLocationManagerDelegate, ReachabilityDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        delegate?.slackStatusManager(self, didUpdate: currentOffice)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard NSScreen.hasActiveDisplay() else {
            print("🛑 No hay pantalla disponible")
            return
        }
        guard !paused else {
            print("🛑 Estás en modo pausa")
            return
        }
        let office = Office.given(ssid: Office.SSID.current(), currentLocation: locations.last)
        print("Ubicación identificada como \"\(office.text)\"")
        sendToSlack(office: office)
    }
    
    func reachability(_ reachability: Reachability, didUpdateInternetStatus isAvailable: Bool) {
        if isAvailable {
            print("✅ Internet disponible - iniciando seguimiento de ubicación")
            startTracking()
        } else {
            print("❌ Internet no disponible - deteniendo seguimiento de ubicación")
            locationManager.stopUpdatingLocation()
        }
    }
}
