//
//  AppDelegate.swift
//  MOSSU
//
//  Created by Javier Querol on 5/9/22.
//

import Cocoa
import KeyboardShortcuts
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    private var statusBarController: StatusBarController?
    private let notifier = NotificationManager()
    private let slackManager = SlackStatusManager()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window = NSWindow()
        SelectionReader.resetStaleAuthorizationAfterUpdate()
        statusBarController = StatusBarController()
        QuickLinkStore.shared.registerHandlers()
        LAPSManager.shared.configure { [weak self] title, body in
            // El usuario acaba de pedirlo: se avisa aunque esté en modo vacaciones.
            self?.sendNotification(text: title, body: body, ignoringMute: true)
        }
        KeyboardShortcuts.onKeyUp(for: .lapsElevate) {
            LAPSManager.shared.run()
        }
        SettingsModel.shared.configure(
            slackManager: slackManager,
            launchAtLoginManager: launchAtLoginManager,
            checkForUpdates: { [weak self] in self?.checkForUpdates() },
            showLogs: { [weak self] in self?.showLogs() },
            startHoliday: { [weak self] date in self?.startHoliday(until: date) }
        )
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(settingsDidChange),
                                               name: .settingsDidChange,
                                               object: nil)
        updateStatusMenu()
        slackManager.delegate = self
        slackManager.allowNextUpdateBypassingScheduleRestrictions()
//        UserDefaults.standard.removeObject(forKey: "token")
//        UserDefaults.standard.removeObject(forKey: "mutedUntil")
        
        showFirstLaunchPopupIfNeeded()

        // Enable "launch at login" by default on first run
        if !UserDefaults.standard.bool(forKey: "hasSetLaunchAtLoginDefault") {
            launchAtLoginManager.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "hasSetLaunchAtLoginDefault")
        }
        
        if let token = UserDefaults.standard.string(forKey: "token") {
            slackManager.token = token
            slackManager.getCurrentStatus(token: token)
            if slackManager.meetingIntegrationEnabled {
                slackManager.requestCalendarAccess()
            }
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
                
                LogManager.shared.log("Received token from url: \(token ?? "nil")")
                
                if let token = token {
                    slackManager.token = token
                    slackManager.requestAuthorization()
                    slackManager.currentOffice = nil
                    slackManager.allowNextUpdateBypassingScheduleRestrictions()
                    slackManager.getCurrentStatus(token: token)
                    if slackManager.meetingIntegrationEnabled {
                        slackManager.requestCalendarAccess()
                    }
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
    
    func startHoliday(until date: Date) {
        slackManager.sendHoliday(until: date)
        // Si la fecha de vuelta no valía, no hay vacaciones que anunciar en el menú.
        guard slackManager.isOnHoliday else { return }
        updateStatusMenu(office: holiday)
    }

    @objc func startTracking() {
        slackManager.startTracking()
    }

    @objc func checkForUpdates() {
        DispatchQueue.main.async {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            self.updaterController.checkForUpdates(nil)
        }
    }

    @objc func runLAPS() {
        LAPSManager.shared.run()
    }

    @objc func showSettings() {
        SettingsWindowController.shared.show(tab: .general)
    }

    @objc func showQuickLinks() {
        SettingsWindowController.shared.show(tab: .shortcuts)
    }

    @objc private func settingsDidChange() {
        refreshStatusMenu()
        // Las vacaciones también caducan solas: la ventana de ajustes abierta ha de enterarse.
        SettingsModel.shared.refresh()
    }

    private func refreshStatusMenu() {
        if let office = slackManager.currentOffice {
            updateStatusMenu(office: office)
        } else {
            updateStatusMenu()
        }
    }

    @objc func showLogs() {
        let alert = NSAlert()
        alert.messageText = "Últimos eventos de MOSSU"
        
        let logs = LogManager.shared.getAllLogs()
        let logsText = logs.isEmpty ? "No hay logs disponibles" : logs.map { $0.formattedString }.joined(separator: "\n")
        
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 250))
        textView.string = logsText
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 680, height: 250))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        
        alert.accessoryView = scrollView
        alert.addButton(withTitle: "Cerrar")
        
        alert.runModal()
    }
    
    private func showFirstLaunchPopupIfNeeded() {
        let hasShownFirstLaunchPopup = UserDefaults.standard.bool(forKey: "hasShownFirstLaunchPopup")
        
        if !hasShownFirstLaunchPopup {
            let alert = NSAlert()
            alert.messageText = "¡Bienvenido a MOSSU!"
            alert.informativeText = "MOSSU ahora vive únicamente en la barra de estado del Mac (arriba a la derecha). Haz clic en el icono de MOSSU para acceder a todas las opciones de la aplicación."
            alert.addButton(withTitle: "Entendido")
            alert.alertStyle = .informational
            
            // Mostrar el alert y marcar como visto
            alert.runModal()
            UserDefaults.standard.set(true, forKey: "hasShownFirstLaunchPopup")
        }
    }
    
    private func updateStatusMenu(text: String? = nil, office: Office? = nil) {
        guard let statusBarController = self.statusBarController else { return }
        LogManager.shared.log("Actualizando el menu a \"\(text ?? office?.text ?? "")\"")
        statusBarController.update(validToken: slackManager.token != nil,
                                   text: text,
                                   office: office,
                                   lastUpdate: slackManager.lastUpdate,
                                   name: slackManager.name,
                                   paused: slackManager.paused,
                                   holidayEndDate: slackManager.activeHolidayEndDate)
    }

    private func sendNotification(text: String, body: String? = nil, ignoringMute: Bool = false) {
        LogManager.shared.log("📣 Enviado notificación: \(text)")
        notifier.send(text: text, body: body, ignoringMute: ignoringMute)
    }
}

extension AppDelegate: SlackStatusManagerDelegate {
    func slackStatusManager(_ manager: SlackStatusManager, didUpdate office: Office?) {
        updateStatusMenu(office: office)
        // Para que "Última actualización" de la ventana de ajustes no se quede atrás.
        SettingsModel.shared.refresh()
    }

    func slackStatusManager(_ manager: SlackStatusManager, showMessage text: String) {
        sendNotification(text: text)
    }

    func slackStatusManagerDidUpdateCalendarPreferences(_ manager: SlackStatusManager) {
        SettingsModel.shared.refresh()
        refreshStatusMenu()
    }
}
