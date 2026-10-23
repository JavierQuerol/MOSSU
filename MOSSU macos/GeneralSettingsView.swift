import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var model = SettingsModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Inicio") {
                Toggle("Abrir MOSSU al iniciar sesión", isOn: $model.launchAtLoginEnabled)
            }

            SettingsSection(title: "Barra de menús") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Ocultar el icono de batería mientras el Mac está enchufado", isOn: $model.hidesBatteryIconWhilePluggedIn)
                    Text("Vuelve a aparecer al desenchufarlo. Para aplicar el cambio, MOSSU reinicia Centro de control y los iconos de la derecha de la barra parpadean un momento.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
