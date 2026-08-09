import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Elevar a administrador 45 minutos con LAPS. Por defecto ⌃⌥L, como en LAPS 45.
    static let lapsElevate = Self("lapsElevate", default: .init(.l, modifiers: [.control, .option]))
}

/// Automatiza el flujo de LAPS del Intelligent Hub:
/// Hub → Apps → LAPS Run/Rerun → diálogo de swiftDialog → 45 min → OK.
///
/// El AppleScript se ejecuta DENTRO del proceso de MOSSU: así macOS atribuye el permiso
/// de Accesibilidad a MOSSU y no a `/usr/bin/osascript`, que devolvería -25211.
final class LAPSManager {
    static let shared = LAPSManager()

    /// El flujo vive en disco para poder ajustarlo si cambia la interfaz del Hub,
    /// sin recompilar ni publicar una versión nueva.
    static let flowPath = NSString(string: "~/Library/Application Support/MOSSU/laps-flow.applescript")
        .expandingTildeInPath

    /// Lo que concede el flujo: el radio 3 del diálogo son 45 minutos.
    static let elevationDuration: TimeInterval = 45 * 60

    private(set) var isRunning = false

    private var notifyAction: ((String, String) -> Void)?
    private var cachedAdminCheck: (isAdmin: Bool, checkedAt: Date)?
    private let adminCacheTTL: TimeInterval = 15
    private let elevationGrace: TimeInterval = 120
    private let elevationDateKey = "lapsElevationDate"
    private var adminWatchTimer: Timer?
    /// Hasta cuándo tiene sentido cerrar el Hub tras una elevación recién pedida.
    private var closeHubDeadline: Date?

    private init() {}

    func configure(notify: @escaping (String, String) -> Void) {
        notifyAction = notify
        installFlowIfNeeded()
        syncShortcutAvailability()

        // El estado admin puede cambiar sin que MOSSU intervenga (caduca solo, o lo
        // concede otro), así que se vigila para reactivar el atajo en cuanto expire.
        adminWatchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshAdminState()
        }
    }

    /// El atajo solo existe cuando NO eres admin: LAPS no permite renovar la elevación.
    private func syncShortcutAvailability() {
        if isAdmin {
            KeyboardShortcuts.disable(.lapsElevate)
        } else {
            KeyboardShortcuts.enable(.lapsElevate)
        }
    }

    private func refreshAdminState() {
        let previous = cachedAdminCheck?.isAdmin
        cachedAdminCheck = nil
        let current = isAdmin

        syncShortcutAvailability()
        closeHubIfElevated()
        if previous != current {
            LogManager.shared.log(current ? "🔐 LAPS: admin activo" : "🔐 LAPS: la elevación ha terminado")
            notifyMenu()
        }
    }

    /// El Hub lo abre MOSSU solo para pedir la elevación, así que una vez conseguida
    /// se cierra. Se hace con `NSRunningApplication`, no con AppleScript, para no pedir
    /// un permiso de Automatización más y para poder condicionarlo a ser admin de verdad.
    private func closeHubIfElevated() {
        guard let deadline = closeHubDeadline else { return }

        guard Date() < deadline else {
            // La elevación no llegó a aplicarse: no cerrar el Hub más tarde por sorpresa.
            closeHubDeadline = nil
            return
        }

        guard isAdmin else { return }
        closeHubDeadline = nil
        closeIntelligentHub()
    }

    private func closeIntelligentHub() {
        // Solo apps con icono en el Dock: los agentes en segundo plano del MDM no se tocan.
        let hubs = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && ($0.localizedName ?? "").localizedCaseInsensitiveContains("Intelligent Hub")
        }

        guard !hubs.isEmpty else { return }

        for hub in hubs where !hub.terminate() {
            LogManager.shared.log("🔐 LAPS: el Hub no aceptó cerrarse")
        }
        LogManager.shared.log("🔐 LAPS: Hub cerrado tras conseguir admin")
    }

    // MARK: - Estado

    /// Pertenencia al grupo `admin`. Se cachea unos segundos porque el menú se reconstruye a menudo.
    var isAdmin: Bool {
        if let cached = cachedAdminCheck, Date().timeIntervalSince(cached.checkedAt) < adminCacheTTL {
            return cached.isAdmin
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/id")
        process.arguments = ["-Gn"]
        let pipe = Pipe()
        process.standardOutput = pipe

        var groups = ""
        do {
            try process.run()
            groups = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            process.waitUntilExit()
        } catch {
            LogManager.shared.log("🔐 LAPS: no pude comprobar los grupos (\(error.localizedDescription))")
        }

        let isAdmin = groups.split(whereSeparator: { $0 == " " || $0 == "\n" }).contains("admin")
        cachedAdminCheck = (isAdmin, Date())
        if !isAdmin, let start = elevationDate, Date().timeIntervalSince(start) > elevationGrace {
            // Ha caducado (o la ha quitado otro): olvidar cuándo empezó. Durante los
            // primeros segundos no se toca: la elevación tarda un poco en aplicarse.
            elevationDate = nil
        }
        return isAdmin
    }

    /// Cuándo elevó MOSSU por última vez. Nil si no lo sabe: si la elevación se pidió
    /// desde el propio Hub, MOSSU solo puede saber que eres admin, no desde cuándo.
    private var elevationDate: Date? {
        get { UserDefaults.standard.object(forKey: elevationDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: elevationDateKey) }
    }

    /// Tiempo que queda de elevación, o nil si no hay forma de saberlo.
    var remainingElevation: TimeInterval? {
        guard isAdmin, let start = elevationDate else { return nil }

        let remaining = Self.elevationDuration - Date().timeIntervalSince(start)
        guard remaining > 0 else {
            // Sigues siendo admin más allá de los 45 min: la cuenta ya no vale, no la enseñes.
            elevationDate = nil
            return nil
        }
        return remaining
    }

    // MARK: - Ejecución

    func run() {
        guard !isRunning else { return }

        // Defensivo: el atajo está desregistrado y la fila del menú deshabilitada,
        // pero entre la caducidad y el siguiente repaso puede colarse una llamada.
        guard !isAdmin else {
            LogManager.shared.log("🔐 LAPS: ya eres admin, LAPS no permite renovar")
            return
        }

        // Sin Accesibilidad no se puede pilotar el Hub.
        guard SelectionReader.hasAccessibilityPermission else {
            LogManager.shared.log("🔐 LAPS cancelado: falta permiso de Accesibilidad")
            SelectionReader.requestAccessibilityPermission()
            notifyAction?("MOSSU necesita permiso de Accesibilidad",
                          "Actívalo para que MOSSU pueda pilotar el Intelligent Hub.")
            return
        }

        isRunning = true
        cachedAdminCheck = nil
        LogManager.shared.log("🔐 LAPS: pidiendo admin 45 min…")
        notifyMenu()

        let source = flowSource
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // NSAppleScript se crea y se ejecuta en el mismo hilo.
            let result = Self.runAppleScript(source)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRunning = false
                self.cachedAdminCheck = nil
                self.handle(output: result.output, error: result.error)
                self.syncShortcutAvailability()
                self.notifyMenu()

                // La elevación tarda unos segundos en aplicarse: repasar poco después
                // para desregistrar el atajo sin esperar al repaso de cada minuto.
                Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                    self?.refreshAdminState()
                }
            }
        }
    }

    private func notifyMenu() {
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private static func runAppleScript(_ source: String) -> (output: String, error: String) {
        guard let script = NSAppleScript(source: source) else {
            return ("", "no pude compilar el AppleScript del flujo")
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo = errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "error desconocido"
            let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            return ("", "\(message) (\(number))")
        }

        return (result.stringValue ?? "", "")
    }

    private func handle(output: String, error: String) {
        LogManager.shared.log("🔐 LAPS resultado -> salida=[\(output)] error=[\(error)]")

        guard error.isEmpty else {
            let lowercased = error.lowercased()
            if error.contains("-25211") || lowercased.contains("acceso de ayuda") || lowercased.contains("assistive") {
                notifyAction?("Falta permiso de Accesibilidad",
                              "Activa MOSSU en Ajustes → Privacidad y seguridad → Accesibilidad.")
                SelectionReader.openAccessibilitySettings()
            } else {
                notifyAction?("LAPS: no se pudo completar", error)
            }
            return
        }

        if output.contains("SELECCIONADO_45M") {
            elevationDate = Date()
            // La elevación tarda unos segundos: el Hub se cierra en cuanto se confirme,
            // aquí o en el repaso posterior del estado admin.
            closeHubDeadline = Date().addingTimeInterval(300)
            closeHubIfElevated()

            if isAdmin {
                notifyAction?("Admin activado 45 min", "LAPS ha concedido permisos de administrador.")
            } else {
                notifyAction?("45 min solicitado", "La elevación puede tardar unos segundos en aplicarse.")
            }
        } else if output.contains("YA_ADMIN") {
            notifyAction?("Ya eras administrador", "No hacía falta elevar; aviso cerrado.")
        } else if output.contains("SIN_DIALOGO") {
            notifyAction?("No apareció el selector", "LAPS no mostró el diálogo de tiempo. Inténtalo de nuevo en unos segundos.")
        } else {
            notifyAction?("LAPS", output.isEmpty ? "Terminado." : output)
        }
    }

    // MARK: - Flujo editable

    /// Lee el flujo de disco en cada ejecución; si falta, usa el embebido.
    private var flowSource: String {
        if let external = try? String(contentsOfFile: Self.flowPath, encoding: .utf8),
           !external.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return external
        }
        LogManager.shared.log("🔐 LAPS: no pude leer \(Self.flowPath); uso el flujo embebido")
        return Self.embeddedFlow
    }

    private func installFlowIfNeeded() {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: Self.flowPath) else { return }
        writeEmbeddedFlow()
    }

    func revealFlowInFinder() {
        if !FileManager.default.fileExists(atPath: Self.flowPath) {
            writeEmbeddedFlow()
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Self.flowPath)])
    }

    func restoreDefaultFlow() {
        writeEmbeddedFlow()
        LogManager.shared.log("🔐 LAPS: flujo restaurado al original")
    }

    private func writeEmbeddedFlow() {
        let directory = (Self.flowPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try Self.embeddedFlow.write(toFile: Self.flowPath, atomically: true, encoding: .utf8)
            LogManager.shared.log("🔐 LAPS: flujo instalado en \(Self.flowPath)")
        } catch {
            LogManager.shared.log("🔐 LAPS: no pude instalar el flujo (\(error.localizedDescription))")
        }
    }

    /// Flujo por defecto. Devuelve SELECCIONADO_45M | YA_ADMIN | SIN_DIALOGO, o lanza error.
    private static let embeddedFlow = #"""
    -- Flujo LAPS 45m. Fichero editable: MOSSU lo lee en cada ejecución, sin recompilar.
    -- Devuelve: SELECCIONADO_45M | YA_ADMIN | SIN_DIALOGO  (o lanza error con el motivo)

    on findByTwo(el, a, b)
        set elName to ""
        set kids to {}
        tell application "System Events"
            try
                set elName to name of el
            end try
            try
                set kids to UI elements of el
            end try
        end tell
        try
            if elName is not missing value and (elName contains a) and (elName contains b) then return el
        end try
        repeat with k in kids
            set f to my findByTwo(k, a, b)
            if f is not missing value then return f
        end repeat
        return missing value
    end findByTwo

    -- Garantiza que el Hub tiene ventana abierta. `open -a` envía el evento "reopen",
    -- que es lo único que la restaura si el usuario la cerró (activate no basta).
    on ensureHubWindow()
        repeat 6 times
            tell application "System Events"
                set n to 0
                try
                    set n to count of windows of process "Intelligent Hub"
                end try
            end tell
            if n > 0 then return true
            try
                do shell script "/usr/bin/open -a 'Workspace ONE Intelligent Hub'"
            end try
            delay 2.5
        end repeat
        tell application "System Events"
            set n to 0
            try
                set n to count of windows of process "Intelligent Hub"
            end try
        end tell
        return (n > 0)
    end ensureHubWindow

    if not my ensureHubWindow() then error "No consigo abrir la ventana del Hub."

    tell application "System Events"
        tell process "Intelligent Hub"
            set frontmost to true
            try
                click button "Apps" of window 1
            end try
            delay 2.2
        end tell
    end tell

    -- Buscar el botón de LAPS, reintentando (la vista tarda en pintarse)
    set btn to missing value
    repeat 5 times
        tell application "System Events"
            try
                set btn to my findByTwo(window 1 of process "Intelligent Hub", "LAPS", "Run")
            end try
        end tell
        if btn is not missing value then exit repeat
        delay 1.5
    end repeat
    if btn is missing value then error "No encuentro el botón Run/Rerun de LAPS en el Hub."

    tell application "System Events" to click btn

    -- Esperar el diálogo de swiftDialog
    set dlgUp to false
    repeat 60 times
        delay 1
        tell application "System Events"
            try
                if (count of windows of (first application process whose name is "Dialog")) > 0 then
                    set dlgUp to true
                    exit repeat
                end if
            end try
        end tell
    end repeat
    if not dlgUp then return "SIN_DIALOGO"

    -- Actuar sin pausas: el diálogo se auto-cierra en pocos segundos.
    -- Radios sin etiqueta accesible; orden 1=15m, 2=30m, 3=45m. OK = botón por defecto (Return).
    delay 0.8
    set outcome to ""
    tell application "System Events"
        tell (first application process whose name is "Dialog")
            set frontmost to true
            set hasRadios to false
            try
                set rg to radio group 1 of group 1 of window 1
                if (count of radio buttons of rg) ≥ 3 then set hasRadios to true
            end try
            if hasRadios then
                click radio button 3 of rg
                delay 0.4
                key code 36
                set outcome to "SELECCIONADO_45M"
            else
                try
                    key code 36
                end try
                set outcome to "YA_ADMIN"
            end if
        end tell
    end tell

    delay 3
    return outcome
    """#
}
