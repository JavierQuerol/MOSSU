import Cocoa
import CoreLocation

protocol SlackStatusManagerDelegate: AnyObject {
    func slackStatusManager(_ manager: SlackStatusManager, didUpdate office: Office?)
    func slackStatusManager(_ manager: SlackStatusManager, showMessage text: String)
}

class SlackStatusManager: NSObject {
    weak var delegate: SlackStatusManagerDelegate?

    var token: String?
    var name: String = "El muchacho"
    var paused: Bool = false
    var lastUpdate: Date?
    var currentOffice: Office? {
        didSet { delegate?.slackStatusManager(self, didUpdate: currentOffice) }
    }

    private let locationManager = CLLocationManager()
    private let reachability = Reachability()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    func startTracking() {
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
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
            case .failure:
                UserDefaults.standard.removeObject(forKey: "token")
                self.token = nil
            }
            self.reachability.startInternetTracking { [weak self] hasInternet in
                guard let self = self else { return }
                if hasInternet {
                    self.startTracking()
                }
            }
        }
    }

    func sendHoliday() {
        paused = true
        sendToSlack(office: holiday)
    }

    func togglePause() {
        paused.toggle()
        if !paused {
            startTracking()
        }
    }

    private func sendToSlack(office: Office) {
        locationManager.stopUpdatingLocation()
        if currentOffice != nil {
            let weekday = Calendar.current.component(.weekday, from: Date())
            let hour = Calendar.current.component(.hour, from: Date())
            if Office.unavailableDays.contains(weekday) {
                let df = DateFormatter()
                df.locale = Locale(identifier: "es_ES")
                let dayName = df.weekdaySymbols[weekday - 1]
                delegate?.slackStatusManager(self, showMessage: "Los \(dayName)s no se actualiza Slack")
                return
            }
            if hour >= Office.workingHoursEnd || hour < Office.workingHoursStart {
                delegate?.slackStatusManager(self, showMessage: "Después de las \(Office.workingHoursEnd):00h no se actualiza Slack")
                return
            }
        }
        
        guard let token = token else { return }
        Slack.update(given: office, token: token) { [weak self] error in
            guard let self = self else { return }
            print("actualizado correctamente a \(office.text)")
            self.lastUpdate = Date()
            if error == nil, self.currentOffice != office {
                self.currentOffice = office
                self.delegate?.slackStatusManager(self, showMessage: office.text)
            } else {
                self.token = nil
            }
        }
    }
}

extension SlackStatusManager: CLLocationManagerDelegate {
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
        sendToSlack(office: office)
    }
}
