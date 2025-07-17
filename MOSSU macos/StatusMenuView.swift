import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var slackManager: SlackStatusManager
    var delegate: AppDelegate

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }

    private var dayFormatter: DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }

    var body: some View {
        Group {
            if slackManager.token == nil {
                Button("🔴 Requiere autorización") { delegate.showAuth() }
                Divider()
            }
            if let office = slackManager.currentOffice {
                Text("\(slackManager.name) está \(office.text)")
            }
            let dateString = dateFormatter.string(from: slackManager.lastUpdate ?? Date())
            Text("Actualizado el \(dateString)")
            Divider()
            Button(slackManager.paused ? "▶️ Reanudar actualizaciones" : "⏸️ Pausar actualizaciones") {
                delegate.pauseOrResumeUpdates()
            }
            if let endDate = slackManager.holidayEndDate, slackManager.paused {
                Text("🌴 Vacaciones hasta \(dayFormatter.string(from: endDate))")
            } else {
                Button("🌴 Activar modo vacaciones") { delegate.setHoliday() }
            }
            Divider()
            Button("Buscar actualizaciones…") { delegate.checkForUpdates() }
            Divider()
            Button("Salir") { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
    }
}

