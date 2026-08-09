import AppKit
import SwiftUI

/// Ventana única de ajustes. MOSSU corre como accessory, así que hay que pasar a
/// `.regular` mientras está abierta para que pueda coger el foco.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController.make()

    static var isWindowVisible: Bool {
        shared.window?.isVisible == true
    }

    private var didCenter = false

    private static func make() -> SettingsWindowController {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Ajustes de MOSSU"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false

        // El tamaño se fija aquí y no con `idealWidth`/`idealHeight` en SwiftUI: con un
        // frame flexible, NSHostingController resuelve al mínimo y los ideales se ignoran.
        window.contentMinSize = NSSize(width: 700, height: 480)
        window.setContentSize(preferredContentSize())

        let controller = SettingsWindowController(window: window)
        window.delegate = controller
        return controller
    }

    /// Tamaño de arranque, acotado a lo que quepa en la pantalla del portátil.
    private static func preferredContentSize() -> NSSize {
        var size = NSSize(width: 760, height: 680)
        if let visible = NSScreen.main?.visibleFrame {
            size.width = min(size.width, visible.width - 40)
            size.height = min(size.height, visible.height - 40)
        }
        return size
    }

    func show(tab: SettingsModel.Tab) {
        SettingsModel.shared.selectedTab = tab
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        if !didCenter {
            window?.center()
            didCenter = true
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}
