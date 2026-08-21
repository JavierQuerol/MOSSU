import SwiftUI

struct ScheduleSettingsView: View {
    @ObservedObject private var model = SettingsModel.shared
    @State private var holidayDate = Date().addingTimeInterval(86400)

    private let hourColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Estado de Slack") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lastUpdateText)
                            Text("Vuelve a mirar la red y la ubicación y actualiza tu estado, aunque estés fuera del horario.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Button("Actualizar ahora") { model.forceUpdate() }
                            .disabled(model.updatesPaused)
                    }

                    Divider()

                    Toggle("Pausar las actualizaciones de estado", isOn: $model.updatesPaused)
                    Text("Mientras esté pausado, MOSSU deja de tocar tu estado de Slack.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsSection(title: "Vacaciones") {
                holidayControls
            }

            Text("MOSSU solo actualiza tu estado en Slack los días y las horas que marques. Fuera de ese horario no toca nada.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsSection(title: "Días") {
                HStack(spacing: 6) {
                    ForEach(model.weekdays, id: \.number) { day in
                        ScheduleChip(title: day.symbol, isOn: model.isDayEnabled(day.number)) {
                            model.toggleDay(day.number)
                        }
                    }
                }
            }

            SettingsSection(title: "Horas") {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: hourColumns, spacing: 6) {
                        ForEach(model.selectableHours, id: \.self) { hour in
                            ScheduleChip(title: String(format: "%02d:00", hour),
                                         isOn: model.isHourEnabled(hour)) {
                                model.toggleHour(hour)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button("Todas") { model.setAllHours(enabled: true) }
                        Button("Ninguna") { model.setAllHours(enabled: false) }
                        Spacer(minLength: 0)
                        Text("Deja fuera la hora de comer si no quieres que te cambie el estado.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var holidayControls: some View {
        if let endDate = model.holidayEndDate {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Estás de vacaciones. Vuelves el \(Self.dateFormatter.string(from: endDate)).")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("MOSSU ha puesto el estado de vacaciones y no lo cambiará hasta que vuelvas.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Cancelar") { model.cancelHoliday() }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    DatePicker("Vuelvo el", selection: $holidayDate, in: Self.firstReturnDate..., displayedComponents: .date)
                        .datePickerStyle(.field)
                    Text("Pausa MOSSU y pone tu estado de vacaciones hasta que vuelvas.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Activar vacaciones") { model.startHoliday(until: holidayDate) }
            }
        }
    }

    private var lastUpdateText: String {
        guard let lastUpdate = model.lastUpdate else {
            return "MOSSU todavía no ha actualizado tu estado."
        }
        return "Última actualización: \(Self.updateFormatter.string(from: lastUpdate))"
    }

    private static let updateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    /// Volver hoy no son vacaciones: lo antes que se puede volver es mañana.
    private static var firstReturnDate: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}

/// Chip pulsable para días y horas: más directo que una lista de checkmarks.
private struct ScheduleChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15))
                )
                .foregroundColor(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
