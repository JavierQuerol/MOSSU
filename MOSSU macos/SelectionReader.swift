import AppKit
import ApplicationServices

/// Lee el texto seleccionado en la app en primer plano.
///
/// Estrategia híbrida:
///   1. API de Accesibilidad (`AXSelectedText` del elemento con foco) — limpio e instantáneo,
///      pero no todas las apps lo exponen (Electron, algunos webviews).
///   2. Fallback: simular ⌘C, leer el portapapeles y restaurarlo después.
///
/// Ambas vías requieren el permiso de Accesibilidad. Sin él devuelve nil
/// (y muestra una única vez por sesión el aviso del sistema para concederlo).
enum SelectionReader {
    private static var didPromptForAccessibility = false

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Devuelve el texto seleccionado, o nil si no hay selección o falta permiso.
    /// El completion se ejecuta en el hilo principal.
    static func readSelectedText(completion: @escaping (String?) -> Void) {
        guard AXIsProcessTrusted() else {
            promptForAccessibilityOnce()
            completion(nil)
            return
        }

        if let text = axSelectedText(), !text.isEmpty {
            completion(text)
            return
        }

        copySelectionViaCmdC(completion: completion)
    }

    // MARK: - Permiso

    private static let lastRunBuildKey = "lastRunBuild"

    /// Al actualizar, la concesión de Accesibilidad puede quedar huérfana: el interruptor
    /// sigue activado en Ajustes del sistema pero macOS ya no confía en el binario nuevo,
    /// y desde la app no hay salida (el diálogo de conceder no aparece si ya estás en la
    /// lista). Si al arrancar una versión distinta el permiso no es efectivo, se borra la
    /// entrada para que se pueda volver a pedir limpia.
    static func resetStaleAuthorizationAfterUpdate() {
        let defaults = UserDefaults.standard
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let previousBuild = defaults.string(forKey: lastRunBuildKey)
        defaults.set(currentBuild, forKey: lastRunBuildKey)

        guard previousBuild != currentBuild else { return }
        // Si el permiso funciona, la entrada está sana: tocarla solo daría trabajo al usuario.
        guard !AXIsProcessTrusted() else { return }

        let from = previousBuild ?? "desconocida"
        LogManager.shared.log("🔐 Actualización (\(from) → \(currentBuild)) sin Accesibilidad efectiva: reseteando el permiso")
        resetAccessibilityAuthorization()
    }

    /// En una instalación nueva no hay entrada que borrar y `tccutil` no hace nada.
    private static func resetAccessibilityAuthorization() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleIdentifier]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                LogManager.shared.log("🔐 Permiso de Accesibilidad reseteado: vuelve a concederlo cuando lo necesites")
            } else {
                LogManager.shared.log("🔐 tccutil devolvió \(process.terminationStatus) al resetear Accesibilidad")
            }
        } catch {
            LogManager.shared.log("🔐 No se pudo ejecutar tccutil: \(error.localizedDescription)")
        }
    }

    /// Muestra el diálogo del sistema para conceder Accesibilidad (botón de la ventana de ajustes).
    static func requestAccessibilityPermission() {
        didPromptForAccessibility = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func promptForAccessibilityOnce() {
        guard !didPromptForAccessibility else { return }
        LogManager.shared.log("⌨️ Atajo cancelado: falta permiso de Accesibilidad")
        requestAccessibilityPermission()
    }

    // MARK: - Vía 1: Accesibilidad (AXSelectedText)

    private static func axSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focused as! AXUIElement

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
              let text = selectedRef as? String else {
            return nil
        }
        return text
    }

    // MARK: - Vía 2: ⌘C simulado con restauración del portapapeles

    private static func copySelectionViaCmdC(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let savedChangeCount = pasteboard.changeCount

        postCmdC()

        poll(timeout: 0.35, condition: { pasteboard.changeCount != savedChangeCount }) { copied in
            let text = copied ? pasteboard.string(forType: .string) : nil
            restore(saved, to: pasteboard)
            completion((text?.isEmpty == false) ? text : nil)
        }
    }

    private static func postCmdC() {
        let keyC: CGKeyCode = 8 // kVK_ANSI_C
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        // Flags explícitos: solo ⌘, aunque el usuario aún mantenga pulsados los
        // modificadores del hotkey al dispararse el keyUp.
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func poll(timeout: TimeInterval,
                             interval: TimeInterval = 0.03,
                             elapsed: TimeInterval = 0,
                             condition: @escaping () -> Bool,
                             completion: @escaping (Bool) -> Void) {
        if condition() { completion(true); return }
        if elapsed >= timeout { completion(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            poll(timeout: timeout, interval: interval, elapsed: elapsed + interval,
                 condition: condition, completion: completion)
        }
    }

    // MARK: - Snapshot / restauración del portapapeles

    private static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [:]) { acc, type in
                acc[type] = item.data(forType: type)
            }
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
