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
        //UserDefaults.standard.removeObject(forKey: "token")
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
                    UserDefaults.standard.set(token, forKey: "token")
                    slackManager.token = token
                    slackManager.requestAuthorization()
                    slackManager.currentOffice = nil
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
        slackManager.sendHoliday()
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
        print(text ?? office?.text ?? "")
        guard let statusBarController = self.statusBarController else { return }
        statusBarController.update(validToken: slackManager.token != nil,
                                   text: text,
                                   office: office,
                                   lastUpdate: slackManager.lastUpdate,
                                   name: slackManager.name,
                                   paused: slackManager.paused,
                                   authSelector: #selector(showAuth),
                                   pauseSelector: #selector(pauseOrResumeUpdates),
                                   holidaySelector: #selector(setHoliday),
                                   updateSelector: #selector(checkForUpdates))
    }
    
    private func sendNotification(text: String) {
        notifier.send(text: text)
    }
}

extension AppDelegate: SlackStatusManagerDelegate {
    func slackStatusManager(_ manager: SlackStatusManager, didUpdate office: Office?) {
        updateStatusMenu(office: office)
    }

    func slackStatusManager(_ manager: SlackStatusManager, showMessage text: String) {
        print(text)
        sendNotification(text: text)
    }
}

