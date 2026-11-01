import AppKit
import Combine
import SwiftUI

/// Ventana única de ajustes. MOSSU corre como accessory, así que hay que pasar a
/// `.regular` mientras está abierta para que pueda coger el foco.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController.make()

    static var isWindowVisible: Bool {
        shared.window?.isVisible == true
    }

    private var didCenter = false
    private var titleSubscription: AnyCancellable?

    private static func make() -> SettingsWindowController {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        // Como en Ajustes del Sistema: el contenido ocupa también la barra de título
        // para que la barra lateral llegue hasta arriba, y la barra de herramientas
        // (vacía) pone el título encima de la sección, no encima de la barra lateral.
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        // El tamaño se fija aquí y no con `idealWidth`/`idealHeight` en SwiftUI: con un
        // frame flexible, NSHostingController resuelve al mínimo y los ideales se ignoran.
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.setContentSize(preferredContentSize())

        let controller = SettingsWindowController(window: window)
        window.delegate = controller
        // La ventana se titula con la sección abierta, también al cambiarla desde la barra lateral.
        controller.titleSubscription = SettingsModel.shared.$selectedTab.sink { [weak window] tab in
            window?.title = tab.title
        }
        return controller
    }

    /// Tamaño de arranque, acotado a lo que quepa en la pantalla del portátil.
    private static func preferredContentSize() -> NSSize {
        var size = NSSize(width: 900, height: 720)
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
