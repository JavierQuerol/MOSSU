import Combine
import Foundation
import KeyboardShortcuts

/// Almacena los atajos del usuario en UserDefaults y mantiene registrados sus handlers.
/// La combinación de teclas de cada atajo la persiste KeyboardShortcuts por su cuenta.
final class QuickLinkStore: ObservableObject {
    static let shared = QuickLinkStore()

    private let storageKey = "quickLinks"
    private var registeredIDs: Set<UUID> = []

    @Published private(set) var links: [QuickLink] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([QuickLink].self, from: data) {
            links = stored
        }
    }

    /// Registra los handlers de todos los atajos guardados. Se llama al arrancar.
    func registerHandlers() {
        links.forEach(register)
    }

    @discardableResult
    func addLink() -> QuickLink {
        let link = QuickLink()
        links.append(link)
        register(link)
        persist()
        return link
    }

    func updateTemplate(_ template: String, for id: UUID) {
        guard let index = links.firstIndex(where: { $0.id == id }),
              links[index].urlTemplate != template else { return }
        links[index].urlTemplate = template
        persist()
    }

    func remove(_ link: QuickLink) {
        links.removeAll { $0.id == link.id }
        registeredIDs.remove(link.id)
        KeyboardShortcuts.removeHandler(for: link.shortcutName)
        KeyboardShortcuts.setShortcut(nil, for: link.shortcutName)
        persist()
    }

    /// `onKeyUp` acumula handlers, así que solo se registra una vez por atajo.
    /// El handler busca el atajo por id para no quedarse con una URL obsoleta.
    private func register(_ link: QuickLink) {
        guard !registeredIDs.contains(link.id) else { return }
        registeredIDs.insert(link.id)

        let id = link.id
        KeyboardShortcuts.onKeyUp(for: link.shortcutName) { [weak self] in
            guard let link = self?.links.first(where: { $0.id == id }) else { return }
            QuickLinkRunner.run(link)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}
