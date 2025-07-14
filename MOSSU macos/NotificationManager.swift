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

    func send(text: String) {
        guard notificationsAuthorized else { return }
        if let muteDate = mutedUntil, Date() < muteDate { return }

        let content = UNMutableNotificationContent()
        content.title = text
        content.sound = UNNotificationSound.default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
