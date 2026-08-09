import UserNotifications

class NotificationManager {
    private var notificationsAuthorized = false
    private var mutedUntil: Date?

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            self?.notificationsAuthorized = granted
        }
        if let storedDate = UserDefaults.standard.object(forKey: "mutedUntil") as? Date {
            mutedUntil = storedDate
        }
    }

    func mute(until date: Date) {
        mutedUntil = date
        UserDefaults.standard.set(date, forKey: "mutedUntil")
    }

    /// `ignoringMute` para avisos que el usuario acaba de pedir: silenciarlos por
    /// estar de vacaciones dejaría la acción sin respuesta.
    func send(text: String, body: String? = nil, ignoringMute: Bool = false) {
        guard notificationsAuthorized else { return }
        if !ignoringMute, let muteDate = mutedUntil, Date() < muteDate { return }

        let content = UNMutableNotificationContent()
        content.title = text
        if let body = body {
            content.body = body
        }
        content.sound = UNNotificationSound.default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
