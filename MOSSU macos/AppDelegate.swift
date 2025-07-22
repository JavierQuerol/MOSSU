//
//  AppDelegate.swift
//  MOSSU
//
//  Created by Javier Querol on 5/9/22.
//

import Cocoa
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    private var statusBarController: StatusBarController?
    private let notifier = NotificationManager()
    private let slackManager = SlackStatusManager()
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window = NSWindow()
        statusBarController = StatusBarController()
        updateStatusMenu()
        slackManager.delegate = self
//        UserDefaults.standard.removeObject(forKey: "token")
//        UserDefaults.standard.removeObject(forKey: "mutedUntil")
        if let token = UserDefaults.standard.string(forKey: "token") {
            slackManager.token = token
            slackManager.getCurrentStatus(token: token)
        } else {
            showAuth()
        }
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "mossu", url.host == "oauth" else { continue }

            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems {
                
                let token = queryItems.first(where: { $0.name == "token" })?.value
                
                print("Received token from url: \(token ?? "nil")")
                
                if let token = token {
                    slackManager.token = token
                    slackManager.requestAuthorization()
                    slackManager.currentOffice = nil
                    slackManager.getCurrentStatus(token: token)
                    startTracking()
                }
            }
        }
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    @objc func showAuth() {
        var slackOAuthURL: URL? {
            var components = URLComponents(string: "https://slack.com/oauth/v2/authorize")
            components?.queryItems = [
                URLQueryItem(name: "client_id", value: Constants.SLACK_CLIENT_ID),
                URLQueryItem(name: "user_scope", value: Constants.SLACK_USER_SCOPE.joined(separator: ",")),
                URLQueryItem(name: "redirect_uri", value: Constants.SLACK_REDIRECT_URI)
            ]
            return components?.url
        }
        if let url = slackOAuthURL {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func setHoliday() {
        let alert = NSAlert()
        alert.messageText = "Modo vacaciones"
        alert.informativeText = "Selecciona hasta cuándo quieres pausar las notificaciones"
        let datePicker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 150, height: 150))
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.dateValue = Date().addingTimeInterval(86400)
        datePicker.datePickerStyle = .clockAndCalendar
        alert.accessoryView = datePicker
        alert.addButton(withTitle: "Aceptar")
        alert.addButton(withTitle: "Cancelar")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            slackManager.sendHoliday(until: datePicker.dateValue)
            updateStatusMenu(office: holiday)
        }
    }

    @objc func pauseOrResumeUpdates() {
        slackManager.togglePause()
        print(slackManager.paused ? "Actualización pausada" : "Reanudando actualizaciones")
        if let office = slackManager.currentOffice {
            updateStatusMenu(office: office)
        }
    }

    @objc func startTracking() {
        slackManager.startTracking()
    }

    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
    
    private func updateStatusMenu(text: String? = nil, office: Office? = nil) {
        guard let statusBarController = self.statusBarController else { return }
        print("Actualizando el menu a \"\(text ?? office?.text ?? "")\"")
        statusBarController.update(validToken: slackManager.token != nil,
                                   text: text,
                                   office: office,
                                   lastUpdate: slackManager.lastUpdate,
                                   name: slackManager.name,
                                   paused: slackManager.paused,
                                   holidayEndDate: slackManager.holidayEndDate,
                                   authSelector: #selector(showAuth),
                                   pauseSelector: #selector(pauseOrResumeUpdates),
                                   holidaySelector: #selector(setHoliday),
                                   updateSelector: #selector(checkForUpdates))
    }
    
    private func sendNotification(text: String) {
        print("Enviado notificación: \(text)")
        notifier.send(text: text)
    }
}

extension AppDelegate: SlackStatusManagerDelegate {
    func slackStatusManager(_ manager: SlackStatusManager, didUpdate office: Office?) {
        updateStatusMenu(office: office)
    }

    func slackStatusManager(_ manager: SlackStatusManager, showMessage text: String) {
        sendNotification(text: text)
    }
}

