import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var model = SettingsModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Inicio") {
                Toggle("Abrir MOSSU al iniciar sesión", isOn: $model.launchAtLoginEnabled)
            }

            SettingsSection(title: "Versión de MOSSU") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Versión \(model.appVersion)")
                        Text("MOSSU busca e instala actualizaciones automáticamente una vez al día.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button("Buscar ahora…") { model.checkForUpdates() }
                }
            }

            SettingsSection(title: "Diagnóstico") {
                HStack(alignment: .firstTextBaseline) {
                    Text("Consulta qué ha hecho MOSSU: cambios de estado, red, calendario y atajos.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("Ver registro…") { model.showLogs() }
                }
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
