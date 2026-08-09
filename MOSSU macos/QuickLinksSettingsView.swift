import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

/// Ventana de configuración de los atajos rápidos. Es el único sitio donde se
/// crean, editan y borran: el menú de la barra solo los muestra.
struct QuickLinksSettingsView: View {
    @ObservedObject private var store = QuickLinkStore.shared
    @State private var accessibilityGranted = SelectionReader.hasAccessibilityPermission
    @State private var focusedLinkID: UUID?

    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !accessibilityGranted {
                permissionBanner
                Divider()
            }

            lapsSection
            Divider()

            Text("Atajos personalizados")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            if store.links.isEmpty {
                emptyState
            } else {
                columnHeaders
                list
            }

            addButton
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { accessibilityGranted = SelectionReader.hasAccessibilityPermission }
        .onReceive(permissionTimer) { _ in
            // El permiso se concede fuera de la app, así que hay que refrescarlo solo.
            accessibilityGranted = SelectionReader.hasAccessibilityPermission
        }
    }

    // MARK: - Permiso

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text("MOSSU necesita permiso de Accesibilidad para leer el texto seleccionado y para pilotar el Intelligent Hub.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Conceder…") { SelectionReader.requestAccessibilityPermission() }
                    Button("Abrir Ajustes del sistema…") { SelectionReader.openAccessibilitySettings() }
                    Button("Reiniciar MOSSU") { restartApp() }
                }
                Text("Si MOSSU ya aparece activado en la lista, el permiso quedó huérfano tras una actualización: quítalo con el botón −, reinicia MOSSU y vuelve a concederlo.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    /// Relanza MOSSU: los cambios de Accesibilidad se aplican de forma fiable en el
    /// arranque siguiente. Se espera a que este proceso muera antes de abrir el nuevo
    /// para no tener dos instancias peleándose por los atajos globales.
    private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier

        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = [
            "-c",
            "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"\(bundlePath)\""
        ]

        do {
            try relauncher.run()
        } catch {
            LogManager.shared.log("No pude programar el reinicio: \(error.localizedDescription)")
            return
        }

        NSApp.terminate(nil)
    }

    // MARK: - Acción integrada (LAPS)

    private var lapsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Acciones de MOSSU")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Activar admin 45 minutos (LAPS)")
                    Text("Abre el Intelligent Hub, lanza LAPS y elige 45 minutos sin que toques el ratón. Mientras ya eres administrador el atajo queda inactivo: LAPS no permite renovar.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                KeyboardShortcuts.Recorder(for: .lapsElevate)
                    .frame(width: 140)
            }

            HStack(spacing: 8) {
                Text("El flujo es un AppleScript editable: ajústalo si cambia la interfaz del Hub.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Mostrar flujo…") { LAPSManager.shared.revealFlowInFinder() }
                Button("Restaurar") { LAPSManager.shared.restoreDefaultFlow() }
            }
        }
        .padding(16)
    }

    // MARK: - Lista

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Text("URL")
            Spacer(minLength: 0)
            Text("Atajo").frame(width: 176, alignment: .leading)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Sin scroll propio: la pestaña entera ya scrollea, y anidar dos scrolls
    /// hace que el trackpad no sepa cuál mover.
    private var list: some View {
        VStack(spacing: 14) {
            ForEach(store.links) { link in
                QuickLinkRow(link: link, focusedLinkID: $focusedLinkID)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text("Todavía no tienes atajos")
                .font(.headline)
            Text("Añade uno con una URL como https://bob.prod.monline/catalog/\(QuickLink.selectionToken)?search=\(QuickLink.selectionToken) y la combinación de teclas que quieras.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
    }

    private var addButton: some View {
        Button {
            let link = store.addLink()
            focusedLinkID = link.id
        } label: {
            Label("Añadir atajo", systemImage: "plus.circle")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Pie

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Escribe \(QuickLink.selectionToken) donde quieras insertar el texto que tengas seleccionado.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Insertar \(QuickLink.selectionToken)") { insertToken() }
        }
        .padding(16)
    }

    /// Inserta el token en el cursor del campo que se está editando. Si no hay
    /// ninguno en edición, lo añade al final del último campo enfocado.
    private func insertToken() {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
            editor.insertText(QuickLink.selectionToken, replacementRange: editor.selectedRange())
            return
        }

        guard let id = focusedLinkID ?? store.links.last?.id,
              let link = store.links.first(where: { $0.id == id }) else { return }
        store.updateTemplate(link.urlTemplate + QuickLink.selectionToken, for: id)
    }
}

// MARK: - Fila

private struct QuickLinkRow: View {
    let link: QuickLink
    @Binding var focusedLinkID: UUID?

    @State private var template: String
    @FocusState private var isFocused: Bool

    init(link: QuickLink, focusedLinkID: Binding<UUID?>) {
        self.link = link
        _focusedLinkID = focusedLinkID
        _template = State(initialValue: link.urlTemplate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("https://ejemplo.com/\(QuickLink.selectionToken)", text: $template)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($isFocused)
                    .onChange(of: template) { newValue in
                        QuickLinkStore.shared.updateTemplate(newValue, for: link.id)
                    }
                    .onChange(of: isFocused) { focused in
                        if focused { focusedLinkID = link.id }
                    }

                KeyboardShortcuts.Recorder(for: link.shortcutName)
                    .frame(width: 140)

                Button {
                    QuickLinkStore.shared.remove(link)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Eliminar atajo")
            }

            previewLine
        }
        .onChange(of: link.urlTemplate) { newValue in
            // Sincroniza cuando la plantilla cambia desde fuera (botón "Insertar").
            if newValue != template { template = newValue }
        }
    }

    @ViewBuilder
    private var previewLine: some View {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            Text("Pega la URL y graba una combinación de teclas.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if let preview = QuickLinkRunner.preview(for: trimmed) {
            Text("→ \(preview.absoluteString)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("URL no válida")
                .font(.caption)
                .foregroundColor(.red)
        }
    }
}
