import Foundation
import KeyboardShortcuts

/// Un atajo global definido por el usuario: una plantilla de URL y la combinación de
/// teclas que la dispara. No tiene nombre: la etiqueta del menú se deriva de la URL.
struct QuickLink: Codable, Identifiable, Equatable {
    /// Token que se sustituye por el texto seleccionado al disparar el atajo.
    static let selectionToken = "{selection}"

    /// Forma corta, aceptada también al construir la URL.
    static let shortSelectionToken = "{}"

    static var selectionTokens: [String] { [selectionToken, shortSelectionToken] }

    /// Cómo se representa el token en el menú, donde el espacio es escaso.
    static let selectionSymbol = "‹›"

    let id: UUID
    var urlTemplate: String

    init(id: UUID = UUID(), urlTemplate: String = "") {
        self.id = id
        self.urlTemplate = urlTemplate
    }

    /// Nombre dinámico bajo el que KeyboardShortcuts persiste la combinación de teclas.
    var shortcutName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("quickLink-\(id.uuidString)")
    }

    /// Etiqueta para el menú: host y ruta, sin esquema ni query, truncada por el medio.
    /// Devuelve nil si la plantilla no produce una URL válida.
    var menuTitle: String? {
        guard QuickLinkRunner.preview(for: urlTemplate) != nil else { return nil }

        var display = urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if let schemeRange = display.range(of: "://") {
            display = String(display[schemeRange.upperBound...])
        }
        if let queryIndex = display.firstIndex(of: "?") {
            display = String(display[..<queryIndex])
        }
        // El token completo se come media fila del menú: aquí basta con marcar el hueco.
        display = Self.selectionTokens.reduce(display) {
            $0.replacingOccurrences(of: $1, with: Self.selectionSymbol)
        }
        return display.truncatedInMiddle(limit: 42)
    }
}
