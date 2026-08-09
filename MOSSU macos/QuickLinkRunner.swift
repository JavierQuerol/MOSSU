import AppKit

/// Construye y abre la URL de un atajo sustituyendo `{selection}` por el texto
/// seleccionado en la app en primer plano.
enum QuickLinkRunner {
    /// Valor de ejemplo para la vista previa de la ventana de ajustes.
    static let sampleSelection = "23053"

    private enum Component {
        case path
        case query
    }

    /// Lee la selección y abre la URL resultante en el navegador por defecto.
    static func run(_ link: QuickLink) {
        SelectionReader.readSelectedText { selection in
            let text = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !text.isEmpty else {
                LogManager.shared.log("⌨️ Atajo cancelado: no hay texto seleccionado")
                NSSound.beep()
                return
            }

            guard let url = buildURL(template: link.urlTemplate, selection: text) else {
                LogManager.shared.log("⌨️ Atajo cancelado: URL no válida (\(link.urlTemplate))")
                NSSound.beep()
                return
            }

            LogManager.shared.log("⌨️ Abriendo \(url.absoluteString)")
            NSWorkspace.shared.open(url)
        }
    }

    /// URL que produciría la plantilla con un valor de ejemplo, o nil si no es válida.
    static func preview(for template: String) -> URL? {
        buildURL(template: template, selection: sampleSelection)
    }

    /// Sustituye el token codificando según dónde caiga: ruta antes del primer `?`,
    /// parámetro de consulta después.
    static func buildURL(template: String, selection: String) -> URL? {
        var trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }

        let (path, query) = splitAtQuery(trimmed)
        var composed = QuickLink.selectionTokens.reduce(path) {
            $0.replacingOccurrences(of: $1, with: encoded(selection, for: .path))
        }
        if let query = query {
            composed += "?" + QuickLink.selectionTokens.reduce(query) {
                $0.replacingOccurrences(of: $1, with: encoded(selection, for: .query))
            }
        }

        guard let url = URL(string: composed), url.host?.isEmpty == false else { return nil }
        return url
    }

    private static func splitAtQuery(_ string: String) -> (path: String, query: String?) {
        guard let index = string.firstIndex(of: "?") else { return (string, nil) }
        return (String(string[..<index]), String(string[string.index(after: index)...]))
    }

    private static func encoded(_ text: String, for component: Component) -> String {
        switch component {
        case .path:
            return text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
        case .query:
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&+=?#")
            return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        }
    }
}
