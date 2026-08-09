import SwiftUI

struct CalendarSettingsView: View {
    @ObservedObject private var model = SettingsModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Reuniones") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Cambiar mi estado durante las reuniones", isOn: $model.meetingIntegrationEnabled)
                    Text("Mientras tengas un evento en curso, MOSSU pone el emoji de reunión y lo retira al terminar.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.meetingIntegrationEnabled {
                SettingsSection(title: "Calendarios observados") {
                    if model.calendarPermissionsGranted {
                        calendarList
                    } else {
                        permissionRow
                    }
                }
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("MOSSU necesita acceso a tu calendario para saber cuándo estás en una reunión.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button("Conceder acceso…") { model.requestCalendarAccess() }
        }
    }

    @ViewBuilder
    private var calendarList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Todos los calendarios", isOn: $model.watchesAllCalendars)

            if model.availableCalendars.isEmpty {
                Text("No hay calendarios disponibles.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.availableCalendars) { calendar in
                            Toggle(isOn: binding(for: calendar)) {
                                HStack(spacing: 6) {
                                    Text(calendar.title)
                                    if !calendar.source.isEmpty, calendar.source != calendar.title {
                                        Text(calendar.source)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: min(CGFloat(model.availableCalendars.count) * 24 + 8, 170))
                .disabled(model.watchesAllCalendars)
                .opacity(model.watchesAllCalendars ? 0.5 : 1)
            }
        }
    }

    private func binding(for calendar: SettingsModel.CalendarOption) -> Binding<Bool> {
        Binding(
            get: { model.isCalendarSelected(calendar.id) },
            set: { _ in model.toggleCalendar(calendar.id) }
        )
    }
}
