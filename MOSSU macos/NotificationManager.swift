import UserNotifications

class NotificationManager {
    private var notificationsAuthorized = false

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            self?.notificationsAuthorized = granted
        }
    }

    func send(text: String) {
        guard notificationsAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = text
        content.sound = UNNotificationSound.default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
