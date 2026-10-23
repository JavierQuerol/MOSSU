import AppKit
import IOKit.ps

/// Oculta el icono de batería de la barra de menús mientras el Mac está enchufado y
/// lo vuelve a mostrar al pasar a batería.
///
/// macOS no tiene API para esto: el icono es de Centro de control, que lee sus
/// preferencias al arrancar. Así que se reescriben y se reinicia Centro de control,
/// que launchd vuelve a lanzar solo.
final class BatteryIconManager {
    static let shared = BatteryIconManager()

    private let enabledKey = "hideBatteryIconWhilePluggedIn"
    private let domain = "com.apple.controlcenter" as CFString
    private let moduleKey = "Battery" as CFString
    // Bits de `moduleKey`. El resto, como el 16 de "Mostrar en Centro de control", se conserva.
    private let shownInMenuBar = 2
    private let hiddenFromMenuBar = 8

    private var pendingUpdate: DispatchWorkItem?
    private var isPoweringOff = false

    private init() {}

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            // Al desactivarlo el icono vuelve a verse: si no, se quedaría oculto.
            setIconVisible(!newValue || isOnBattery)
        }
    }

    func start() {
        // Solo avisa al pasar de enchufado a batería o al revés, no con cada cambio de porcentaje.
        if let source = IOPSCreateLimitedPowerNotification({ _ in
            BatteryIconManager.shared.scheduleUpdate()
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isPoweringOff = true
        }

        scheduleUpdate()
    }

    /// Al salir de MOSSU el icono vuelve a verse, porque ya nadie lo mostraría al
    /// desenchufar. Al cerrar sesión o apagar se deja como está: si no, habría que
    /// reiniciar Centro de control nada más volver a entrar.
    func stop() {
        guard isEnabled, !isPoweringOff else { return }
        setIconVisible(true)
    }

    /// Algunos cargadores conectan y desconectan varias veces al enchufarlos: se espera
    /// a que la corriente se asiente para no reiniciar Centro de control de más.
    private func scheduleUpdate() {
        pendingUpdate?.cancel()
        let update = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled else { return }
            self.setIconVisible(self.isOnBattery)
        }
        pendingUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: update)
    }

    /// Sin datos de la fuente de alimentación se trata como batería: mejor ver el icono
    /// de más que perderlo cuando hace falta.
    private var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return true
        }
        return source as String != kIOPMACPowerKey
    }

    private func setIconVisible(_ visible: Bool) {
        let flags = CFPreferencesCopyValue(moduleKey, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
        let itemKeys = statusItemKeys
        // Sin valor guardado, macOS lo muestra.
        let moduleMatches = (flags.map { $0 & hiddenFromMenuBar == 0 } ?? true) == visible
        let itemsMatch = itemKeys.allSatisfy { (CFPreferencesCopyAppValue($0, domain) as? Bool) == visible }
        if moduleMatches && itemsMatch { return }

        let updated = ((flags ?? 0) & ~(shownInMenuBar | hiddenFromMenuBar)) | (visible ? shownInMenuBar : hiddenFromMenuBar)
        CFPreferencesSetValue(moduleKey, NSNumber(value: updated), domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        for key in itemKeys {
            CFPreferencesSetAppValue(key, NSNumber(value: visible), domain)
        }
        CFPreferencesAppSynchronize(domain)

        LogManager.shared.log(visible ? "🔋 Icono de batería: visible" : "🔌 Icono de batería: oculto")
        restartControlCenter()
    }

    /// AppKit guarda aparte si cada item de la barra está visible, y según la versión de
    /// macOS la clave lleva "CC" o no. Solo se tocan las que ya existen.
    private var statusItemKeys: [CFString] {
        ["NSStatusItem VisibleCC Battery", "NSStatusItem Visible Battery"]
            .map { $0 as CFString }
            .filter { CFPreferencesCopyAppValue($0, domain) != nil }
    }

    /// launchd relanza Centro de control en cuanto muere, pero no más de una vez cada diez
    /// segundos: si se reinicia antes, la derecha de la barra se queda vacía hasta entonces.
    private func restartControlCenter() {
        guard let controlCenter = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return }
        let pid = controlCenter.processIdentifier
        let wait = max(0, 10 - uptime(of: pid))
        // SIGKILL y no SIGTERM: launchd solo lo relanza si no termina limpiamente.
        guard wait > 0 else {
            kill(pid, SIGKILL)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            guard !controlCenter.isTerminated else { return }
            kill(pid, SIGKILL)
        }
    }

    /// `NSRunningApplication.launchDate` es nil para lo que lanza launchd.
    private func uptime(of pid: pid_t) -> TimeInterval {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return .infinity }
        let start = info.kp_proc.p_un.__p_starttime
        return Date().timeIntervalSince1970 - (TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
